module Connectors
  # Runs one sync: fetch raw records via the provider, map them through the
  # connector's field mapping, upsert into the target entity, and write a
  # ConnectorRun. Attributed to the system actor (nil) like other jobs. Every
  # synced record is stamped with its source_connector_id (provenance) and
  # deduped on the operator's own external_id (plus email for contacts/leads).
  module Sync
    module_function

    MAX_RECORDS = 5_000
    STALE_RUN_AFTER = 1.hour

    # docket_field => external_field is the mapping shape; these are the docket
    # fields each target can map. external_id is the dedup key everywhere.
    MAPPABLE_FIELDS = {
      "contacts" => %w[external_id email name phone],
      "leads" => %w[external_id email name phone company_name],
      "deals" => %w[external_id name value],
      "cases" => %w[external_id subject contact_email]
    }.freeze

    def run(connector, trigger: "manual")
      run = claim(connector, trigger)
      return nil unless run

      Current.set(actor: nil) do
        perform(connector, run)
      end
      run
    rescue ActiveRecord::RecordNotUnique
      # The partial unique index is the final defence when two workers race
      # after both being queued. The winner owns the sync; the loser is a no-op.
      nil
    rescue StandardError => e
      connector.update!(status: :error)
      run&.update!(status: :failed, finished_at: Time.current, error: e.message.truncate(500))
      run
    end

    def perform(connector, run)
      created = 0
      updated = 0
      records_in = 0
      capped = false
      fetched = connector.provider_instance.fetch || []
      fetched.each do |raw|
        if records_in >= MAX_RECORDS
          capped = true
          break
        end

        case upsert(connector, raw)
        when :created then created += 1
        when :updated then updated += 1
        end
        records_in += 1
      end
      if capped
        Rails.logger.warn("Connectors::Sync capped connector #{connector.id}: more than #{MAX_RECORDS} fetched")
      end

      connector.update!(last_synced_at: Time.current, status: :active)
      run.update!(status: :success, finished_at: Time.current,
                  records_in: records_in, records_created: created, records_updated: updated)
    end

    # Claim a connector briefly under its row lock. The network request and
    # record writes happen after the lock is released. A stale claim is failed
    # explicitly so an interrupted worker cannot block the connector forever.
    def claim(connector, trigger)
      connector.with_lock do
        now = Time.current
        connector.connector_runs.status_running
          .where("started_at IS NULL OR started_at <= ?", now - STALE_RUN_AFTER)
          .update_all(status: ConnectorRun.statuses.fetch("failed"), finished_at: now,
                      error: "sync claim expired", updated_at: now)
        return nil if connector.connector_runs.status_running.exists?

        connector.connector_runs.create!(trigger: trigger, status: :running, started_at: now)
      end
    end

    def upsert(connector, raw)
      case connector.target
      when "contacts" then upsert_contact(connector, raw)
      when "leads" then upsert_lead(connector, raw)
      when "deals" then upsert_deal(connector, raw)
      when "cases" then upsert_case(connector, raw)
      else :skipped
      end
    end

    # --- contacts ---

    def upsert_contact(connector, raw)
      attrs = map(connector, raw, "contacts")
      return :skipped if attrs[:external_id].blank? && attrs[:email].blank?

      contact = find_contact(attrs)
      if contact
        contact.update!(stamp(connector, attrs.compact, contact))
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

    # --- leads ---

    def upsert_lead(connector, raw)
      attrs = map(connector, raw, "leads")
      return :skipped if attrs[:external_id].blank? && attrs[:email].blank?

      lead = find_by_external_or_email(Lead, attrs)
      if lead
        lead.update!(stamp(connector, attrs.compact, lead))
        :updated
      else
        Lead.create!(attrs.compact
          .reverse_merge(name: attrs[:external_id] || attrs[:email])
          .merge(source_connector_id: connector.id, source: :import))
        :created
      end
    end

    # --- deals ---

    def upsert_deal(connector, raw)
      attrs = map(connector, raw, "deals")
      return :skipped if attrs[:external_id].blank?

      fields = { name: attrs[:name].presence || attrs[:external_id] }
      fields[:value] = attrs[:value] if attrs[:value].present? # virtual setter → value_cents
      fields[:custom_fields] = attrs[:custom_fields] if attrs[:custom_fields].present?

      deal = Deal.find_by(external_id: attrs[:external_id])
      if deal
        deal.update!(stamp(connector, fields, deal))
        :updated
      else
        pipeline = default_pipeline(connector)
        Deal.create!(fields.merge(external_id: attrs[:external_id], pipeline: pipeline,
                                  pipeline_stage: default_stage(connector, pipeline),
                                  source_connector_id: connector.id))
        :created
      end
    end

    # --- cases ---

    def upsert_case(connector, raw)
      attrs = map(connector, raw, "cases")
      return :skipped if attrs[:external_id].blank? || attrs[:subject].blank?

      kase = Case.find_by(external_id: attrs[:external_id])
      if kase
        fields = { subject: attrs[:subject] }
        fields[:custom_fields] = attrs[:custom_fields] if attrs[:custom_fields].present?
        kase.update!(stamp(connector, fields, kase))
        :updated
      else
        Case.create!(external_id: attrs[:external_id], subject: attrs[:subject],
                     contact: resolve_contact(attrs[:contact_email]), custom_fields: attrs[:custom_fields] || {},
                     source_connector_id: connector.id)
        :created
      end
    end

    # --- shared helpers ---

    # field_mapping: { docket_field => external_field }
    def map(connector, raw, target)
      mapping = connector.field_mapping || {}
      attributes = MAPPABLE_FIELDS.fetch(target).each_with_object({}) do |field, acc|
        source = mapping[field].to_s
        next if source.blank?
        value = raw.is_a?(Hash) ? raw[source] : nil
        acc[field.to_sym] = value.to_s.strip.presence
      end
      custom_fields = mapped_custom_fields(mapping, raw, target)
      attributes[:custom_fields] = custom_fields if custom_fields.any?
      attributes
    end

    # Add provenance to a save only when the record isn't already attributed —
    # keeps the first connector that sourced a record.
    def stamp(connector, save_attrs, record)
      save_attrs = save_attrs.dup
      if save_attrs[:custom_fields]
        save_attrs[:custom_fields] = record.custom_fields.to_h.merge(save_attrs[:custom_fields])
      end
      save_attrs[:source_connector_id] = connector.id if record.source_connector_id.nil?
      save_attrs
    end

    def mapped_custom_fields(mapping, raw, target)
      definitions = CustomFieldDefinition.for_resource(target).index_by(&:key)
      mapping.each_with_object({}) do |(docket_field, source), values|
        next unless docket_field.to_s.start_with?("custom_fields.")

        key = docket_field.to_s.delete_prefix("custom_fields.")
        definition = definitions[key]
        raise Connectors::Error, "connector custom field #{key.inspect} is not defined for #{target}" unless definition
        next unless definition.active?

        value = raw.is_a?(Hash) ? raw[source.to_s] : nil
        result = CustomFields::Type.coerce(definition, value)
        unless result.valid?
          raise Connectors::Error, "connector custom field #{key.inspect} is invalid: #{result.error}"
        end
        values[key] = result.value
      end
    end

    def find_by_external_or_email(model, attrs)
      by_ext = attrs[:external_id].present? && model.find_by(external_id: attrs[:external_id])
      return by_ext if by_ext
      attrs[:email].present? && model.find_by(email: attrs[:email])
    end

    def default_pipeline(connector)
      id = connector.config_value("default_pipeline_id")
      pipeline = id.present? && Pipeline.find_by(id: id)
      raise Connectors::Error, "deals sync needs a default_pipeline_id" unless pipeline
      pipeline
    end

    def default_stage(connector, pipeline)
      id = connector.config_value("default_stage_id")
      stage = id.present? && pipeline.pipeline_stages.find_by(id: id)
      stage || pipeline.pipeline_stages.where(is_won: false, is_lost: false).order(:position).first ||
        pipeline.pipeline_stages.order(:position).first ||
        raise(Connectors::Error, "default pipeline has no stages")
    end

    def resolve_contact(email)
      email = email.to_s.strip.downcase.presence
      raise Connectors::Error, "cases sync needs a contact_email mapping" if email.nil?
      Contact.find_by(email: email) || Contact.create!(name: email, email: email)
    end
  end
end
