class CaseSplit
  def self.call(...) = new(...).call

  def initialize(source:, message_ids:, subject:, actor:)
    @source = source
    @message_ids = Array(message_ids).map(&:to_s).uniq
    @subject = subject.to_s.strip
    @actor = actor
  end

  def call
    raise ArgumentError, "select between 1 and 100 messages" unless @message_ids.size.between?(1, 100)
    raise ArgumentError, "subject is required" if @subject.blank?

    messages = @source.messages.where(id: @message_ids).to_a
    raise ActiveRecord::RecordNotFound unless messages.size == @message_ids.size

    created = nil
    Imports::Mode.run do
      Case.transaction do
        @source.lock!
        created = Case.create!(
          subject: @subject, description: I18n.t("case_split.description", source: @source.tracking_id),
          contact: @source.contact, queue: @source.queue, category: @source.category,
          assignee: @source.assignee, owner: @source.owner, sla_policy: @source.sla_policy,
          priority: @source.priority, channel: :staff
        )
        messages.each { |message| message.update!(case: created) }
        @source.messages.create!(kind: :internal_note, author: @actor,
                                 body: I18n.t("case_split.source_note", target: created.tracking_id))
        created.messages.create!(kind: :internal_note, author: @actor,
                                 body: I18n.t("case_split.target_note", source: @source.tracking_id))
      end
    end
    created
  end
end
