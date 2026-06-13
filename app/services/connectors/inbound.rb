module Connectors
  # The inbound half of omnichannel (PG2): turn a provider's normalized webhook
  # messages into case activity. For each message we resolve/dedupe a Contact
  # from the sender, thread onto the sender's open Case for this connector (or
  # open a new one on the provider's channel), and append an inbound Message.
  #
  # Tenant-aware by construction: the caller (the webhook controller) has
  # already resolved the tenant (primary in isolated, subdomain in shared) and
  # found the connector tenant-scoped, so every record created here lands in
  # that tenant. Attributed to the system actor (the sender authors the
  # message); Case/Message are Audited models, so the trail is automatic.
  module Inbound
    module_function

    # → the Array of Cases that received a message (may repeat across a batch).
    def process(connector, payload)
      Array(connector.provider_instance.ingest(payload)).filter_map do |msg|
        ingest_one(connector, msg)
      end
    end

    def ingest_one(connector, msg)
      contact = resolve_contact(connector, msg)
      kase    = find_or_open_case(connector, contact, msg)
      append_message(kase, contact, msg)
      kase
    end

    # Dedupe on the channel-scoped external id (e.g. "whatsapp:9198…"), then on
    # a known phone, else create. The external id keeps messaging contacts
    # reachable even when they have no email.
    def resolve_contact(connector, msg)
      sender = msg[:sender] || {}
      ext = "#{msg[:channel]}:#{sender[:external_id]}"
      existing = Contact.find_by(external_id: ext)
      # Fall back to a bare-phone match ONLY for unverified contacts (no
      # external_id) — never thread a spoofable inbound number onto a contact
      # verified through another channel (SSO/portal/sync identity) (M2). Mirrors
      # Connectors::Sync#find_contact.
      existing ||= Contact.where(external_id: nil).find_by(phone: sender[:phone]) if sender[:phone].present?
      existing || Contact.create!(
        name: sender[:name].presence || ext,
        phone: sender[:phone].presence,
        external_id: ext,
        source_connector: connector
      )
    end

    # Thread onto this contact's open case for this connector+conversation; open
    # a new one otherwise. Keyed on (connector, thread) so distinct chats stay
    # distinct even for the same contact.
    def find_or_open_case(connector, contact, msg)
      thread = msg[:external_thread_id].to_s
      if thread.present?
        open = Case.open_cases
                   .where(source_connector_id: connector.id, source_thread_id: thread)
                   .order(created_at: :desc).first
        return open if open
      end

      Case.create!(
        subject: msg[:body].to_s.strip.truncate(120).presence || I18n.t("connectors.inbound.no_subject"),
        contact: contact,
        channel: msg[:channel],
        source_connector: connector,
        source_thread_id: thread.presence,
        queue_id: Setting.get("default_queue_id")
      )
    end

    def append_message(kase, contact, msg)
      kase.messages.create!(
        kind: :public_reply,
        direction: :inbound,
        author: contact,
        body: msg[:body].to_s.presence || "(empty message)",
        metadata: { "channel" => msg[:channel], "external_message_id" => msg[:external_message_id] }.compact
      )
    end
  end
end
