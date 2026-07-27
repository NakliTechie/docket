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

      Mode.run do
        ActiveRecord::Base.transaction do
          organisations = import_companies
          contacts = import_contacts(organisations)
          import_tickets(contacts)
          raise ActiveRecord::Rollback if @dry_run
        end
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
        # Freshdesk custom statuses are ints >= 8 and every desk of any size has
        # them. Falling back to :new turned a closed archive into an open
        # backlog, so an unknown status resolves by the ticket's own resolution
        # data before it guesses.
        kase.status = STATUS_MAP.fetch(row["status"]) { status_for_unmapped(row) }

        if kase.save
          # Keep the ticket's real dates. Stamping every case with the migration
          # date destroys backlog age, trend lines and every SLA history number.
          stamp_timestamps(kase, row)
          was_new ? @result.create!("cases") : @result.update!("cases")
          import_conversations(kase, row)
        else
          @result.error!("ticket #{row['id']}: #{kase.errors.full_messages.to_sentence}")
        end
      end
    end

    # created_at/updated_at are attr_readonly-ish in practice (set on insert), so
    # write them straight through rather than fighting AR.
    def stamp_timestamps(record, row)
      created = parse_time(row["created_at"])
      updated = parse_time(row["updated_at"]) || created
      return if created.nil?

      record.update_columns(created_at: created, updated_at: updated)
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      nil
    end

    def status_for_unmapped(row)
      report_unmapped(:status, row["status"])
      # A ticket Freshdesk considers resolved/closed says so in its own fields
      # even under a custom status.
      return :closed if row["closed_at"].present?
      return :resolved if row["resolved_at"].present?

      :new
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

        # `incoming` is Freshdesk's flag for "the customer wrote this". Without
        # it every imported reply defaults to outbound and reads as though staff
        # said it — and outbound public replies are what trigger customer email.
        incoming = conv["incoming"]
        message = kase.messages.create!(
          body: body,
          kind: conv["private"] ? :internal_note : :public_reply,
          direction: incoming ? :inbound : :outbound
        )
        stamp_timestamps(message, conv)
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
