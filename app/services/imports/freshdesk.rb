module Imports
  # Freshdesk migration adapter. It accepts an export payload, a streaming JSON
  # file, or a paginated API source and reconstructs organisations, contacts,
  # explicitly mapped agents, tickets, and conversations under durable source
  # identities.
  class Freshdesk
    STATUS_MAP = {
      2 => :new, 3 => :in_progress, 4 => :resolved, 5 => :closed,
      6 => :waiting_on_customer, 7 => :waiting_on_customer
    }.freeze
    PRIORITY_MAP = { 1 => :low, 2 => :normal, 3 => :high, 4 => :urgent }.freeze
    SOURCE_MAP = {
      1 => :email, 2 => :web_portal, 3 => :phone, 7 => :email,
      9 => :web_portal, 10 => :whatsapp
    }.freeze

    COMPANY_FIELDS = %w[id name description created_at updated_at].freeze
    CONTACT_FIELDS = %w[id name email phone mobile company_id active created_at updated_at].freeze
    AGENT_FIELDS = %w[id contact name email active role role_ids type created_at updated_at].freeze
    TICKET_FIELDS = %w[
      id requester_id responder_id subject description description_text status priority source
      company_id group_id product_id type tags custom_fields email requester created_at updated_at
      due_by fr_due_by resolved_at closed_at first_responded_at conversations attachments
    ].freeze
    CONVERSATION_FIELDS = %w[
      id user_id body body_text private incoming source created_at updated_at attachments
      from_email to_emails cc_emails bcc_emails support_email
    ].freeze

    def self.call(...) = new(...).call

    def initialize(payload: nil, file: nil, source: nil, dry_run: false,
                   default_queue: nil, role_map: {}, status_map: {}, custom_field_map: {},
                   source_instance: "default", resume_token: nil, batch_size: 200)
      @result = Result.new
      @input = Input.new(payload: payload, file: file, source: source, bare_entity: "tickets")
      @source = source
      @export_root = File.dirname(File.expand_path(file)) if file
      @dry_run = dry_run
      @default_queue = default_queue
      @role_map = role_map.stringify_keys
      @status_map = STATUS_MAP.merge(status_map.to_h.transform_keys { |key| integer_key(key) })
      @source_instance = source_instance
      @resume_token = resume_token
      @batch_size = batch_size
      @custom_field_mapping = CustomFields::ImportMapping.new(
        resource_type: "cases", mapping: custom_field_map, result: @result
      )
    rescue JsonRows::FormatError, ArgumentError => e
      @result.error!(e.message)
    end

    def call
      return @result if @result.errors.any?
      unless Features.enabled?("service_desk")
        @result.error!("the service desk module is not enabled for this tenant")
        return @result
      end

      @session = Session.new(source: "freshdesk", source_instance: @source_instance,
                             dry_run: @dry_run, resume_token: @resume_token,
                             batch_size: @batch_size, result: @result)
      @source.watermark = @session.run.previous_watermark if @source&.respond_to?(:watermark=)
      @attachments = Attachments.new(session: @session, downloader: @source,
                                     export_root: @export_root)
      process("companies", optional: true) { |row| import_company(row) }
      process("agents", optional: true) { |row| import_agent(row) }
      process("contacts", optional: true) { |row| import_contact(row) }
      process("tickets") { |row| import_ticket(row) }
      @session.finish!
      @session.result
    rescue JsonRows::FormatError, Session::ResumeError, ActiveRecord::RecordNotFound => e
      @result.error!(e.message)
      @result
    end

    private

    def process(entity, optional: false, &block)
      cursor = ->(row) { @source.cursor_for(entity, row) } if @source && entity == "tickets"
      @session.process(@input.rows(entity, optional: optional), stream: entity,
                       cursor: cursor, &block)
    end

    def import_company(row)
      return invalid_row("company", row) unless row.is_a?(Hash)

      inspect_fields(row, "company", COMPANY_FIELDS)
      external_id = row["id"].to_s
      return missing_identity("company") if external_id.blank?
      return @session.result.skip!("organisations") if row["name"].blank?

      existing = @session.identity_target("company", external_id)
      existing ||= Organisation.find_by(name: row["name"])
      attributes = compact_present(row, name: "name")
      attributes["kind"] = "company" if existing.nil?
      add_source_times(attributes, row)
      @session.sync(source_type: "company", external_id: external_id,
                    kind: "organisations", attributes: attributes,
                    source_updated_at: row["updated_at"], existing: existing) do
        Organisation.new
      end
    end

    def import_agent(row)
      return invalid_row("agent", row) unless row.is_a?(Hash)

      inspect_fields(row, "agent", AGENT_FIELDS)
      external_id = row["id"].to_s
      return missing_identity("agent") if external_id.blank?

      email = row["email"].presence || row.dig("contact", "email").presence
      name = row["name"].presence || row.dig("contact", "name").presence
      role = mapped_role(row)
      if role.nil?
        @session.result.skip!("users")
        return
      end
      if email.blank?
        @session.result.error!("agent #{external_id}: email is required")
        return
      end

      existing = @session.identity_target("agent", external_id)
      existing ||= User.find_by(email_address: email)
      attributes = { "name" => name.presence || email.split("@").first,
                     "email_address" => email }
      attributes["active"] = row["active"] unless row["active"].nil?
      attributes["role"] = role if existing.nil?
      add_source_times(attributes, row)
      @session.sync(source_type: "agent", external_id: external_id, kind: "users",
                    attributes: attributes, source_updated_at: row["updated_at"],
                    existing: existing, metadata: { "mapped_role" => role }) do
        User.new(password: SecureRandom.base64(48))
      end
    end

    def import_contact(row)
      return invalid_row("contact", row) unless row.is_a?(Hash)

      inspect_fields(row, "contact", CONTACT_FIELDS)
      external_id = row["id"].to_s
      return missing_identity("contact") if external_id.blank?

      email = row["email"].presence
      existing = @session.identity_target("contact", external_id)
      existing ||= Contact.find_by(email: email) if email
      if existing&.external_id.present? &&
          @session.identity_target("contact", external_id).nil?
        @session.result.unmapped!("protected_contact", external_id)
        @session.result.skip!("contacts")
        return
      end

      attributes = compact_present(row, name: "name", email: "email")
      if row.key?("phone") || row.key?("mobile")
        attributes["phone"] = row["phone"].presence || row["mobile"].presence
      end
      if row.key?("company_id")
        organisation = @session.identity_target("company", row["company_id"].to_s)
        attributes["organisation_id"] = organisation.id if organisation
        @session.result.unmapped!("company_id", row["company_id"]) if organisation.nil? && row["company_id"].present?
      end
      attributes["name"] ||= email.to_s.split("@").first if existing.nil?
      add_source_times(attributes, row)
      @session.sync(source_type: "contact", external_id: external_id, kind: "contacts",
                    attributes: attributes, source_updated_at: row["updated_at"],
                    existing: existing) { Contact.new }
    end

    def import_ticket(row)
      return invalid_row("ticket", row) unless row.is_a?(Hash)

      inspect_fields(row, "ticket", TICKET_FIELDS)
      external_id = row["id"].to_s
      return missing_identity("ticket") if external_id.blank?

      status = mapped_status(row)
      return @session.result.skip!("tickets") if row.key?("status") && status.nil?

      contact = contact_for(row)
      if contact.nil?
        @session.result.error!("ticket #{external_id}: requester could not be resolved")
        @session.result.skip!("tickets")
        return
      end

      existing = @session.identity_target("ticket", external_id)
      existing ||= Case.with_deleted.find_by(external_id: "freshdesk:#{external_id}")
      existing = nil if existing&.deleted?
      attributes = ticket_attributes(row, contact, existing, status)
      kase = @session.sync(source_type: "ticket", external_id: external_id,
                           kind: "cases", attributes: attributes,
                           source_updated_at: row["updated_at"], existing: existing) do
        Case.new
      end
      import_conversations(kase, row)
      @attachments.import(record: kase, rows: row["attachments"],
                          parent_external_id: external_id,
                          source_type: "ticket_attachment")
      restore_case_history(kase, row)
    end

    def ticket_attributes(row, contact, existing, status)
      attributes = {
        "external_id" => "freshdesk:#{row['id']}",
        "contact_id" => contact.id
      }
      attributes["subject"] = row["subject"].presence || "(no subject)" if row.key?("subject") || existing.nil?
      if row.key?("description_text") || row.key?("description")
        attributes["description"] = strip_html(row["description_text"].presence || row["description"].to_s)
      end
      attributes["status"] = status if status
      attributes["priority"] = mapped_value(PRIORITY_MAP, :priority, row["priority"]) if row.key?("priority")
      attributes["channel"] = mapped_value(SOURCE_MAP, :source, row["source"]) if row.key?("source")
      attributes["queue_id"] = @default_queue&.id if existing.nil? && @default_queue
      source_custom_fields = row["custom_fields"]
      if source_custom_fields.is_a?(Hash)
        FieldContract.new(@session.result, "ticket.custom_fields",
                          @custom_field_mapping.consumed_sources).inspect!(source_custom_fields)
        mapped = @custom_field_mapping.values(source_custom_fields)
        attributes["custom_fields"] = existing&.custom_fields.to_h.merge(mapped) if mapped.any?
        attributes["custom_fields"] ||= mapped if existing.nil? && mapped.any?
      end
      add_source_times(attributes, row, updated: false)
      attributes.compact
    end

    def contact_for(row)
      contact = @session.identity_target("contact", row["requester_id"].to_s)
      return contact if contact

      requester = row["requester"]
      email = row["email"].presence || requester&.dig("email").presence
      return if email.blank?

      source_id = row["requester_id"].presence || "email:#{email.downcase}"
      existing = Contact.find_by(email: email)
      return if existing&.external_id.present?

      attributes = { "email" => email,
                     "name" => requester&.dig("name").presence || email.split("@").first }
      @session.sync(source_type: "contact", external_id: source_id, kind: "contacts",
                    attributes: attributes, existing: existing) { Contact.new }
    end

    def import_conversations(kase, row)
      enumerable(row["conversations"]).each do |conversation|
        next invalid_row("conversation", conversation) unless conversation.is_a?(Hash)

        inspect_fields(conversation, "conversation", CONVERSATION_FIELDS)
        body = strip_html(conversation["body_text"].presence || conversation["body"].to_s)
        next @session.result.skip!("messages") if body.blank?

        external_id = conversation["id"].presence || conversation_digest(kase, conversation, body)
        existing = @session.identity_target("conversation", external_id.to_s)
        attributes = conversation_attributes(kase, conversation, body, external_id)
        message = @session.sync(source_type: "conversation", external_id: external_id,
                                kind: "messages", attributes: attributes,
                                source_updated_at: conversation["updated_at"], existing: existing) do
          Message.new
        end
        @attachments.import(record: message, rows: conversation["attachments"],
                            parent_external_id: external_id,
                            source_type: "conversation_attachment")
      end
    end

    def conversation_attributes(kase, row, body, external_id)
      incoming = row["incoming"] == true
      @session.result.unmapped!("conversation_direction", "missing") unless row.key?("incoming")
      attributes = {
        "case_id" => kase.id,
        "body" => body,
        "kind" => row["private"] ? "internal_note" : "public_reply",
        "direction" => incoming ? "inbound" : "outbound",
        "external_message_id" => "freshdesk:#{external_id}"
      }
      if incoming
        attributes.merge!("author_type" => "Contact", "author_id" => kase.contact_id)
      elsif row["user_id"].present?
        author = @session.identity_target("agent", row["user_id"].to_s)
        if author
          attributes.merge!("author_type" => "User", "author_id" => author.id)
        else
          @session.result.unmapped!("message_author", row["user_id"])
          attributes["source_author_name"] = row["from_email"].presence ||
                                             "Freshdesk agent #{row['user_id']}"
        end
      elsif !incoming && row["from_email"].present?
        attributes["source_author_name"] = row["from_email"]
      end
      add_source_times(attributes, row)
      attributes
    end

    def restore_case_history(kase, row)
      history = {}
      %w[created_at updated_at resolved_at closed_at reopened_at].each do |field|
        history[field] = parse_time(row[field]) if row.key?(field)
      end
      first_response = if row.key?("first_responded_at")
        parse_time(row["first_responded_at"])
      else
        kase.messages.where(direction: :outbound, kind: %i[public_reply agent_turn]).minimum(:created_at)
      end
      history["first_responded_at"] = first_response if first_response

      created = history["created_at"] || kase.created_at
      target = kase.sla_policy&.target_for(kase.priority)
      first_due = parse_time(row["fr_due_by"]) if row.key?("fr_due_by")
      resolution_due = parse_time(row["due_by"]) if row.key?("due_by")
      if target && created
        calendar = kase.sla_policy&.business_calendar || BusinessCalendar.default
        first_due ||= SlaClock.deadline(calendar: calendar, from: created,
                                        minutes: target.first_response_minutes)
        resolution_due ||= SlaClock.deadline(calendar: calendar, from: created,
                                             minutes: target.resolution_minutes)
      end
      history["first_response_due_at"] = first_due if first_due
      history["resolution_due_at"] = resolution_due if resolution_due
      history["first_response_breached"] = first_due && first_response && first_response > first_due
      terminal = history["resolved_at"] || history["closed_at"]
      history["resolution_breached"] = resolution_due && terminal && terminal > resolution_due
      persisted_history = history.compact
      kase.update_columns(persisted_history) if persisted_history.any?
    end

    def mapped_status(row)
      value = row["status"]
      mapped = @status_map[integer_key(value)]
      return mapped if mapped

      @session.result.unmapped!("status", value) unless value.nil?
      @session.result.error!("ticket #{row['id']}: status #{value.inspect} has no mapping")
      nil
    end

    def mapped_role(row)
      candidates = [ row["role"], row["type"], *Array(row["role_ids"]) ].compact.map(&:to_s)
      source_role = candidates.find { |candidate| @role_map.key?(candidate) }
      mapped = @role_map[source_role].to_s if source_role
      return mapped if User.roles.key?(mapped)

      candidates.each { |candidate| @session.result.unmapped!("agent_role", candidate) }
      nil
    end

    def mapped_value(mapping, field, value)
      mapped = mapping[integer_key(value)]
      return mapped if mapped

      @session.result.unmapped!(field, value) unless value.nil?
      nil
    end

    def compact_present(row, mapping)
      mapping.each_with_object({}) do |(target, source), attributes|
        attributes[target.to_s] = row[source] if row.key?(source) && row[source].present?
      end
    end

    def add_source_times(attributes, row, updated: true)
      attributes["created_at"] = parse_time(row["created_at"]) if row.key?("created_at")
      attributes["updated_at"] = parse_time(row["updated_at"]) if updated && row.key?("updated_at")
    end

    def inspect_fields(row, source_type, consumed)
      FieldContract.new(@session.result, source_type, consumed).inspect!(row)
    end

    def invalid_row(type, row)
      @session.result.error!("#{type}: expected an object, got #{row.class}")
    end

    def missing_identity(type)
      @session.result.error!("#{type}: source id is required")
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      @session.result.unmapped!("invalid_timestamp", value)
      nil
    end

    def integer_key(value)
      value.to_s.match?(/\A\d+\z/) ? value.to_i : value
    end

    def conversation_digest(kase, row, body)
      Digest::SHA256.hexdigest([ kase.external_id, row["created_at"], body ].join("\0"))
    end

    def strip_html(text)
      ActionView::Base.full_sanitizer.sanitize(text.to_s).to_s.strip
    end

    def enumerable(value)
      value.is_a?(Array) || value.is_a?(Enumerator) ? value : Array(value)
    end
  end
end
