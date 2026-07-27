module Imports
  # Freshdesk tickets -> cases (plus their requesters -> contacts, and
  # companies -> organisations). Consumes a Freshdesk API export
  # (`{"tickets":[...], "contacts":[...], "companies":[...]}`) or a bare array
  # of tickets, so it runs against a file with no credentials.
  #
  # Idempotent on the Freshdesk ticket id, recorded in the case's external
  # reference, so a re-run updates rather than duplicating.
  class Freshdesk
    # Freshdesk's numeric enums. Anything outside these is reported, not guessed.
    STATUS_MAP = { 2 => :new, 3 => :in_progress, 4 => :resolved, 5 => :closed,
                   6 => :waiting_on_customer, 7 => :waiting_on_customer }.freeze
    PRIORITY_MAP = { 1 => :low, 2 => :normal, 3 => :high, 4 => :urgent }.freeze
    SOURCE_MAP = { 1 => :email, 2 => :web_portal, 3 => :phone, 7 => :email, 9 => :web_portal,
                   10 => :whatsapp }.freeze

    def self.call(...) = new(...).call

    def initialize(payload:, dry_run: false, default_queue: nil)
      @result = Result.new
      @data = parse(payload)
      @dry_run = dry_run
      @default_queue = default_queue
    end

    def call
      unless Features.enabled?("service_desk")
        @result.error!("the service desk module is not enabled for this tenant")
        return @result
      end

      ActiveRecord::Base.transaction do
        organisations = import_companies
        contacts = import_contacts(organisations)
        import_tickets(contacts)
        raise ActiveRecord::Rollback if @dry_run
      end
      @result
    end

    private

    def parse(payload)
      data = payload.is_a?(String) ? JSON.parse(payload) : payload
      data.is_a?(Array) ? { "tickets" => data } : data
    rescue JSON::ParserError => e
      @result.error!("could not parse the export: #{e.message}")
      {}
    end

    def import_companies
      Array(@data["companies"]).each_with_object({}) do |row, map|
        org = Organisation.find_or_initialize_by(name: row["name"].to_s)
        new_record = org.new_record?
        next map[row["id"]] = org if org.name.blank?

        if org.save
          new_record ? @result.create!("organisations") : @result.skip!("organisations")
          map[row["id"]] = org
        else
          @result.error!("company #{row['name']}: #{org.errors.full_messages.to_sentence}")
        end
      end
    end

    def import_contacts(organisations)
      Array(@data["contacts"]).each_with_object({}) do |row, map|
        email = row["email"].presence
        contact = (email && Contact.find_by(email: email)) || Contact.new
        was_new = contact.new_record?
        contact.assign_attributes(
          name: row["name"].presence || email.to_s.split("@").first.to_s,
          email: email, phone: row["phone"].presence || row["mobile"].presence,
          organisation: organisations[row["company_id"]]
        )
        if contact.save
          was_new ? @result.create!("contacts") : @result.update!("contacts")
          map[row["id"]] = contact
        else
          @result.error!("contact #{email}: #{contact.errors.full_messages.to_sentence}")
        end
      end
    end

    def import_tickets(contacts)
      Array(@data["tickets"]).each do |row|
        contact = contacts[row["requester_id"]] || contact_from_ticket(row)
        next @result.skip!("tickets") if contact.nil?

        external = "freshdesk:#{row['id']}"
        kase = Case.with_deleted.find_by(external_id: external)
        was_new = kase.nil?
        kase ||= Case.new(external_id: external, contact: contact,
                          channel: SOURCE_MAP.fetch(row["source"]) { report_unmapped(:source, row["source"]) || :email })

        kase.assign_attributes(
          subject: row["subject"].presence || "(no subject)",
          description: strip_html(row["description_text"].presence || row["description"].to_s),
          priority: PRIORITY_MAP.fetch(row["priority"]) { report_unmapped(:priority, row["priority"]) || :normal },
          queue: kase.queue || @default_queue,
          contact: contact
        )
        # Status is assigned directly rather than through the state machine: an
        # import is reconstructing history, not transitioning through it.
        kase.status = STATUS_MAP.fetch(row["status"]) { report_unmapped(:status, row["status"]) || :new }

        if kase.save
          was_new ? @result.create!("cases") : @result.update!("cases")
          import_conversations(kase, row)
        else
          @result.error!("ticket #{row['id']}: #{kase.errors.full_messages.to_sentence}")
        end
      end
    end

    def contact_from_ticket(row)
      email = row["email"].presence || row.dig("requester", "email").presence
      return nil if email.blank?

      contact = Contact.find_or_initialize_by(email: email)
      contact.name = contact.name.presence || row.dig("requester", "name").presence || email.split("@").first
      contact.save ? contact : nil
    end

    def import_conversations(kase, row)
      Array(row["conversations"]).each do |conv|
        body = strip_html(conv["body_text"].presence || conv["body"].to_s)
        next if body.blank? || kase.messages.exists?(body: body)

        kase.messages.create!(body: body, kind: conv["private"] ? :internal_note : :public_reply)
        @result.create!("messages")
      end
    end

    def strip_html(text) = ActionView::Base.full_sanitizer.sanitize(text.to_s).to_s.strip

    def report_unmapped(field, value)
      @result.unmapped!(field, value) unless value.nil?
      nil
    end
  end
end
