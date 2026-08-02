class LeadMerge
  Error = Class.new(StandardError)

  def self.call(...) = new(...).call

  def initialize(source:, target:, actor:)
    @source = source
    @target = target
    @actor = actor
  end

  def call
    validate!
    Lead.transaction do
      [ @source, @target ].sort_by(&:id).each(&:lock!)
      validate!
      merge_attributes
      move_deals
      move_crm_messages
      move_active_enrollments
      @source.update!(merged_into: @target, merged_at: Time.current)
    end
    @target
  end

  private

  def validate!
    raise Error, "a lead cannot merge into itself" if @source.id == @target.id
    raise Error, "leads must belong to the same tenant" if @source.tenant_id != @target.tenant_id
    raise Error, "source lead is already merged" if @source.merged_into_id?
    raise Error, "target lead is already merged" if @target.merged_into_id?
  end

  def merge_attributes
    attributes = {}
    %i[email phone company_name job_title whatsapp_handle telegram_handle owner_id value_estimate_cents].each do |field|
      attributes[field] = @source.public_send(field) if @target.public_send(field).blank?
    end
    attributes[:email_consent] = @target.email_consent? || @source.email_consent?
    attributes[:sms_consent] = @target.sms_consent? || @source.sms_consent?
    attributes[:consent_captured_at] = [ @target.consent_captured_at, @source.consent_captured_at ].compact.min
    attributes[:consent_source] ||= @target.consent_source.presence || @source.consent_source
    attributes[:notes] = [ @target.notes, @source.notes ].compact_blank.uniq.join("\n\n")
    attributes[:labels] = (@target.labels.to_a + @source.labels.to_a).uniq
    attributes[:custom_fields] = @source.custom_fields.to_h.merge(@target.custom_fields.to_h)
    merge_first_touch(attributes)
    attributes[:provenance] = @target.provenance.to_h.merge(
      "merged_lead_ids" => (@target.provenance.to_h["merged_lead_ids"].to_a + [ @source.id ]).uniq,
      "last_merged_by_id" => @actor&.id
    )
    @target.update!(attributes)
  end

  def merge_first_touch(attributes)
    return unless @source.first_touch_at.present?
    return if @target.first_touch_at.present? && @target.first_touch_at <= @source.first_touch_at

    %i[
      first_touch_campaign_id first_touch_at first_touch_utm_source first_touch_utm_medium
      first_touch_utm_campaign first_touch_utm_term first_touch_utm_content
      first_touch_landing_page first_touch_referrer
    ].each { |field| attributes[field] = @source.public_send(field) }
  end

  def move_deals
    Deal.where(lead: @source).update_all(lead_id: @target.id, updated_at: Time.current)
    if @target.converted_deal_id.blank? && @source.converted_deal_id?
      @target.update!(converted_deal: @source.converted_deal)
    end
  end

  def move_crm_messages
    CrmMessage.where(subject: @source).find_each { |message| message.update!(subject: @target) }
  end

  def move_active_enrollments
    SequenceEnrollment.status_active.where(enrollable: @source).find_each do |enrollment|
      if SequenceEnrollment.status_active.exists?(sequence: enrollment.sequence, enrollable: @target)
        enrollment.cancel!
      else
        enrollment.update!(enrollable: @target)
      end
    end
  end
end
