module Connectors
  # Runs one sync: fetch raw records via the provider, map them through the
  # connector's field mapping, upsert into the target entity, and write a
  # ConnectorRun. Attributed to the system actor (nil) like other jobs.
  module Sync
    module_function

    MAX_RECORDS = 5_000
    CONTACT_FIELDS = %w[name email phone external_id].freeze

    def run(connector, trigger: "manual")
      run = connector.connector_runs.create!(trigger: trigger, status: :running, started_at: Time.current)
      Current.set(actor: nil) do
        perform(connector, run)
      end
      run
    rescue StandardError => e
      connector.update!(status: :error)
      run&.update!(status: :failed, finished_at: Time.current, error: e.message.truncate(500))
      run
    end

    def perform(connector, run)
      records = Array(connector.provider_instance.fetch)
      created = 0
      updated = 0
      records.first(MAX_RECORDS).each do |raw|
        case upsert(connector, raw)
        when :created then created += 1
        when :updated then updated += 1
        end
      end
      connector.update!(last_synced_at: Time.current, status: :active)
      run.update!(status: :success, finished_at: Time.current,
                  records_in: records.size, records_created: created, records_updated: updated)
    end

    def upsert(connector, raw)
      case connector.target
      when "contacts" then upsert_contact(connector, raw)
      else :skipped
      end
    end

    def upsert_contact(connector, raw)
      attrs = map_contact(connector, raw)
      return :skipped if attrs[:external_id].blank? && attrs[:email].blank?

      contact = find_contact(attrs)
      if contact
        save_attrs = attrs.compact
        # Stamp provenance only if unset — keep the first connector that sourced it.
        save_attrs[:source_connector_id] = connector.id if contact.source_connector_id.nil?
        contact.update!(save_attrs)
        :updated
      else
        Contact.create!(attrs.compact
          .reverse_merge(name: attrs[:external_id] || attrs[:email])
          .merge(source_connector_id: connector.id))
        :created
      end
    end

    def find_contact(attrs)
      by_ext = attrs[:external_id].present? && Contact.find_by(external_id: attrs[:external_id])
      return by_ext if by_ext
      # Only dedupe onto unverified contacts by email (mirrors portal intake M9).
      attrs[:email].present? && Contact.where(external_id: nil).find_by(email: attrs[:email])
    end

    # field_mapping: { docket_field => external_field }
    def map_contact(connector, raw)
      mapping = connector.field_mapping || {}
      CONTACT_FIELDS.each_with_object({}) do |field, acc|
        source = mapping[field].to_s
        next if source.blank?
        value = raw.is_a?(Hash) ? raw[source] : nil
        acc[field.to_sym] = value.to_s.strip.presence
      end
    end
  end
end
