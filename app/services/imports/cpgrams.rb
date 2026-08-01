module Imports
  # CPGRAMS (DARPG Centralised Public Grievance Redress & Monitoring System)
  # migration adapter — the government-vertical route in. It reconstructs
  # complainants (Contact) and grievances (Case) with their Action-Taken-Report
  # remarks (Message), keyed on the durable CPGRAMS registration number. Ministry
  # routing maps to a queue only through an explicit queue_map; unmapped
  # dimensions (state, district, unmapped ministries) are reported, never guessed.
  # Pairs with Exports::Cpgrams for the status/ATR round-trip back to CPGRAMS.
  class Cpgrams
    # CPGRAMS lifecycle vocabulary → Docket case status. Compared case-folded so
    # "Under Process" and "under process" both resolve.
    STATUS_MAP = {
      "receipt" => :new, "registered" => :new, "pending" => :new, "fresh" => :new,
      "under process" => :in_progress, "under examination" => :in_progress, "in process" => :in_progress,
      "awaiting citizen" => :waiting_on_customer, "clarification sought" => :waiting_on_customer,
      "disposed of" => :resolved, "disposed" => :resolved, "resolved" => :resolved,
      "closed" => :closed
    }.freeze
    PRIORITY_MAP = {
      "low" => :low, "normal" => :normal, "medium" => :normal,
      "high" => :high, "urgent" => :urgent, "immediate" => :urgent
    }.freeze

    GRIEVANCE_FIELDS = %w[
      registration_number subject grievance_description description status priority ministry
      department state district received_on registered_on closed_on disposed_on updated_at
      complainant remarks
    ].freeze
    COMPLAINANT_FIELDS = %w[name email mobile phone state district address].freeze
    REMARK_FIELDS = %w[id by officer text remark on created_at].freeze

    def self.call(...) = new(...).call

    def initialize(payload: nil, file: nil, dry_run: false, default_queue: nil,
                   status_map: {}, queue_map: {}, source_instance: "default",
                   resume_token: nil, batch_size: 200)
      @result = Result.new
      @input = Input.new(payload: payload, file: file, bare_entity: "grievances")
      @dry_run = dry_run
      @default_queue = default_queue
      @status_map = STATUS_MAP.merge(status_map.to_h.transform_keys { |key| key.to_s.downcase })
      @queue_map = queue_map.to_h.transform_keys { |key| key.to_s.downcase }
      @source_instance = source_instance
      @resume_token = resume_token
      @batch_size = batch_size
    rescue JsonRows::FormatError, ArgumentError => e
      @result.error!(e.message)
    end

    def call
      return @result if @result.errors.any?
      unless Features.enabled?("service_desk")
        @result.error!("the service desk module is not enabled for this tenant")
        return @result
      end

      @session = Session.new(source: "cpgrams", source_instance: @source_instance,
                             dry_run: @dry_run, resume_token: @resume_token,
                             batch_size: @batch_size, result: @result)
      @session.process(@input.rows("grievances"), stream: "grievances") { |row| import_grievance(row) }
      @session.finish!
      @session.result
    rescue JsonRows::FormatError, Session::ResumeError, ActiveRecord::RecordNotFound => e
      @result.error!(e.message)
      @result
    end

    private

    def import_grievance(row)
      return invalid_row("grievance", row) unless row.is_a?(Hash)

      inspect_fields(row, "grievance", GRIEVANCE_FIELDS)
      registration = row["registration_number"].to_s
      return missing_identity("grievance") if registration.blank?

      status = mapped_status(row, registration)
      return @session.result.skip!("grievances") if row.key?("status") && status.nil?

      contact = contact_for(row, registration)
      if contact.nil?
        @session.result.error!("grievance #{registration}: complainant name, email and mobile are all blank")
        return @session.result.skip!("grievances")
      end

      existing = @session.identity_target("grievance", registration)
      existing ||= Case.with_deleted.find_by(external_id: "cpgrams:#{registration}")
      existing = nil if existing&.deleted?
      attributes = grievance_attributes(row, contact, existing, status, registration)
      kase = @session.sync(source_type: "grievance", external_id: registration, kind: "cases",
                           attributes: attributes, source_updated_at: row["updated_at"], existing: existing) do
        Case.new
      end
      import_remarks(kase, row)
      restore_history(kase, row)
    end

    def contact_for(row, registration)
      data = row["complainant"].is_a?(Hash) ? row["complainant"] : {}
      inspect_fields(data, "complainant", COMPLAINANT_FIELDS) if data.any?
      report_unmapped_dimensions(data, registration)

      email = data["email"].presence
      phone = data["mobile"].presence || data["phone"].presence
      name = data["name"].presence
      return nil if name.blank? && email.blank? && phone.blank?

      source_id = email ? "email:#{email.downcase}" : "grievance:#{registration}"
      existing = @session.identity_target("complainant", source_id)
      existing ||= Contact.find_by(email: email) if email
      # A locally-managed contact (its own external_id set outside this import)
      # is never overwritten from a grievance feed.
      return existing if existing && existing.external_id.present? &&
                         @session.identity_target("complainant", source_id).nil?

      attributes = {
        "name" => name.presence || email&.split("@")&.first || "Complainant #{registration}",
        "email" => email, "phone" => phone
      }.compact
      @session.sync(source_type: "complainant", external_id: source_id, kind: "contacts",
                    attributes: attributes, existing: existing) { Contact.new }
    end

    def grievance_attributes(row, contact, existing, status, registration)
      attributes = { "external_id" => "cpgrams:#{registration}", "contact_id" => contact.id,
                     "channel" => "web_portal" }
      if row.key?("subject") || row.key?("grievance_description") || existing.nil?
        subject = row["subject"].presence || truncate_text(row["grievance_description"])
        attributes["subject"] = subject.presence || "(no subject)"
      end
      if row.key?("grievance_description") || row.key?("description")
        attributes["description"] = strip_html(row["grievance_description"].presence || row["description"].to_s)
      end
      attributes["status"] = status if status
      priority = row["priority"].to_s.downcase
      attributes["priority"] = PRIORITY_MAP[priority] if row.key?("priority") && PRIORITY_MAP.key?(priority)
      attributes["queue_id"] = resolved_queue(row)&.id if existing.nil?
      attributes.compact
    end

    def resolved_queue(row)
      ministry = (row["ministry"].presence || row["department"].presence).to_s
      return @default_queue if ministry.blank?

      slug = @queue_map[ministry.downcase]
      queue = CaseQueue.find_by(slug: slug) if slug
      return queue if queue

      @session.result.unmapped!("ministry", ministry) if slug.nil?
      @default_queue
    end

    def import_remarks(kase, row)
      Array(row["remarks"]).each do |remark|
        next @session.result.error!("remark: expected an object, got #{remark.class}") unless remark.is_a?(Hash)

        inspect_fields(remark, "remark", REMARK_FIELDS)
        body = strip_html(remark["text"].presence || remark["remark"].to_s)
        next @session.result.skip!("messages") if body.blank?

        external_id = remark["id"].presence || remark_digest(kase, remark, body)
        existing = @session.identity_target("remark", external_id.to_s)
        attributes = {
          "case_id" => kase.id, "body" => body,
          "kind" => "public_reply", "direction" => "outbound",
          "external_message_id" => "cpgrams:remark:#{external_id}",
          "source_author_name" => (remark["by"].presence || remark["officer"].presence || "CPGRAMS officer")
        }
        attributes["created_at"] = parse_time(remark["on"] || remark["created_at"]) if remark.key?("on") || remark.key?("created_at")
        @session.sync(source_type: "remark", external_id: external_id, kind: "messages",
                      attributes: attributes.compact, existing: existing) { Message.new }
      end
    end

    def restore_history(kase, row)
      history = {}
      created = parse_time(row["received_on"] || row["registered_on"])
      history["created_at"] = created if created
      terminal = parse_time(row["disposed_on"] || row["closed_on"])
      if terminal
        history["resolved_at"] = terminal if kase.status.in?(%w[resolved closed])
        history["closed_at"] = terminal if kase.status == "closed"
      end
      kase.update_columns(history.compact) if history.compact.any?
    end

    def report_unmapped_dimensions(data, registration)
      %w[state district].each do |dimension|
        @session.result.unmapped!(dimension, "#{registration}:#{data[dimension]}") if data[dimension].present?
      end
    end

    def mapped_status(row, registration)
      value = row["status"]
      mapped = @status_map[value.to_s.downcase.strip]
      return mapped if mapped

      @session.result.unmapped!("status", value) unless value.nil?
      @session.result.error!("grievance #{registration}: status #{value.inspect} has no mapping") unless value.nil?
      nil
    end

    def inspect_fields(row, source_type, consumed)
      FieldContract.new(@session.result, source_type, consumed).inspect!(row)
    end

    def invalid_row(type, row)
      @session.result.error!("#{type}: expected an object, got #{row.class}")
    end

    def missing_identity(type)
      @session.result.error!("#{type}: registration_number is required")
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      @session.result.unmapped!("invalid_timestamp", value)
      nil
    end

    def truncate_text(value, limit: 120)
      text = strip_html(value.to_s)
      text.length > limit ? "#{text[0, limit].rstrip}…" : text
    end

    def strip_html(text)
      ActionView::Base.full_sanitizer.sanitize(text.to_s).to_s.strip
    end

    def remark_digest(kase, remark, body)
      Digest::SHA256.hexdigest([ kase.external_id, remark["on"], body ].join("\0"))
    end
  end
end
