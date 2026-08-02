module Connectors
  module TelephonyInbound
    module_function

    TERMINAL_STATUSES = %w[completed failed busy no_answer cancelled].freeze

    def process(connector, payload)
      connector.provider_instance.ingest_calls(payload).map do |event|
        ingest_one(connector, event)
      end
    end

    def ingest_one(connector, event)
      existing = CallRecord.find_by(connector: connector, provider_call_id: event[:provider_call_id])
      return update_existing(existing, event) if existing

      CallRecord.transaction do
        existing = CallRecord.find_by(connector: connector, provider_call_id: event[:provider_call_id])
        next update_existing(existing, event) if existing

        contact = resolve_contact(event[:from_number])
        kase = Case.create!(
          subject: I18n.t("connectors.telephony.subject", number: event[:from_number]),
          contact: contact, channel: :phone,
          source_connector: connector, source_thread_id: event[:provider_call_id],
          queue_id: Setting.get("default_queue_id")
        )
        call_record = CallRecord.create!(attributes_for(event).merge(
          connector: connector, case: kase, contact: contact
        ))
        Current.set(actor: contact) do
          kase.messages.create!(
            kind: :public_reply, direction: :inbound, author: contact,
            source_connector: connector,
            external_message_id: "call:#{event[:provider_call_id]}",
            body: intake_summary(event),
            metadata: { "channel" => "phone", "call_record_id" => call_record.id }
          )
        end
        call_record
      end
    rescue ActiveRecord::RecordNotUnique
      existing = CallRecord.find_by!(connector: connector, provider_call_id: event[:provider_call_id])
      update_existing(existing, event)
    end

    def update_existing(call_record, event)
      attributes = attributes_for(event).compact
      attributes.delete(:status) if event[:status].blank? ||
                                    (terminal?(call_record.status) && !terminal?(event[:status]))
      attributes.delete(:ivr_answers) if event[:ivr_answers].blank?
      attributes.delete(:metadata) if event[:metadata].blank?
      call_record.update!(attributes)
      call_record
    end

    def resolve_contact(number)
      external_id = "phone:#{number}"
      Contact.find_by(external_id: external_id) ||
        Contact.where(external_id: nil).find_by(phone: number) ||
        Contact.create!(name: number, phone: number, external_id: external_id)
    end

    def attributes_for(event)
      {
        provider_call_id: event[:provider_call_id], from_number: event[:from_number],
        to_number: event[:to_number], status: normalized_status(event[:status]),
        recording_url: event[:recording_url], duration_seconds: integer_or_nil(event[:duration_seconds]),
        ivr_answers: event[:ivr_answers] || {}, transcript: event[:transcript],
        metadata: event[:metadata] || {}, started_at: parsed_time(event[:started_at]),
        ended_at: parsed_time(event[:ended_at])
      }
    end

    def intake_summary(event)
      return event[:transcript] if event[:transcript].present?
      return I18n.t("connectors.telephony.ivr_summary", answers: event[:ivr_answers].to_json) if event[:ivr_answers].present?

      I18n.t("connectors.telephony.call_received", number: event[:from_number])
    end

    def normalized_status(value)
      normalized = value.to_s.downcase.tr(" -", "_")
      aliases = { "answered" => "in_progress", "initiated" => "received",
                  "queued" => "received", "canceled" => "cancelled" }
      (aliases[normalized] || normalized).presence_in(CallRecord::STATUSES) || "received"
    end

    def integer_or_nil(value)
      return if value.blank?

      Integer(value, exception: false)
    end

    def parsed_time(value)
      Time.zone.parse(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    def terminal?(status)
      TERMINAL_STATUSES.include?(normalized_status(status))
    end
  end
end
