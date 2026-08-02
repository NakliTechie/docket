module Privacy
  class EraseContact
    class Error < StandardError; end
    class Held < Error; end
    Result = Data.define(:request, :summary)

    def self.call(...) = new(...).call

    def initialize(contact:, requested_by: Current.user)
      @contact = contact
      @tenant = contact.tenant
      @requested_by = requested_by
      @token = contact.erasure_token.presence || SecureRandom.hex(12)
    end

    def call
      existing = @contact.privacy_erasure_requests.status_completed.order(:id).last
      return Result.new(request: existing, summary: existing.summary) if @contact.erased_at? && existing
      hold = @contact.legal_holds.active.first
      raise Held, "contact is under legal hold ##{hold.id}" if hold

      identifiers = direct_identifiers
      request = ActsAsTenant.with_tenant(@tenant) do
        PrivacyErasureRequest.create!(subject: @contact, requested_by: @requested_by,
                                      erasure_token: @token)
      end
      summary = nil
      storage_deletion_ids = []

      ActsAsTenant.with_tenant(@tenant) do
        ApplicationRecord.transaction do
          graph = affected_graph
          redact_audit_entries!(graph, identifiers)
          redact_domain_records!(graph, identifiers)
          storage_deletion_ids = remove_attachments!(graph)
          scrubbed = TenantScrubber.call(tenant: @tenant, identifiers: identifiers, token: @token)
          residue = ResidueScanner.call(tenant: @tenant, identifiers: identifiers)
          unless residue.clean?
            raise Error, "privacy erasure left direct identifiers: #{residue.matches.first(10).inspect}"
          end

          summary = graph.transform_values { |ids| ids.size }.merge("scrubbed_fields" => scrubbed)
          request.update!(status: :completed, completed_at: Time.current, summary: summary)
        end
      end
      storage_deletion_ids.each { |id| StorageDeletionJob.perform_later(id) }
      Result.new(request: request.reload, summary: summary)
    rescue StandardError => e
      request&.update_columns(status: PrivacyErasureRequest.statuses.fetch("failed"),
                              failure_reason: e.message.to_s.truncate(500))
      raise
    end

    private

    def direct_identifiers
      # Only globally scrub strong identity tokens. Narrative fields are
      # redacted directly inside affected_graph; treating a common subject or
      # reply body as an identity could corrupt unrelated customers' evidence.
      values = [ @contact.email, @contact.phone, @contact.external_id ]
      values.compact_blank.map(&:to_s).select { |value| value.length >= 4 }.uniq
    end

    def affected_graph
      case_ids = @contact.cases.with_deleted.pluck(:id)
      message_ids = Message.with_deleted.where(case_id: case_ids).pluck(:id)
      deal_ids = Deal.with_deleted.where(contact_id: @contact.id).pluck(:id)
      lead_ids = Lead.with_deleted.where(contact_id: @contact.id).pluck(:id)
      work_item_ids = WorkLink.where(linkable_type: "Case", linkable_id: case_ids).pluck(:work_item_id)
      comment_ids = WorkComment.with_deleted.where(work_item_id: work_item_ids).pluck(:id)
      notification_ids = Notification.where(notifiable_type: "Case", notifiable_id: case_ids).pluck(:id)
      enrollment_ids = SequenceEnrollment.with_deleted.where(
        enrollable_type: "Contact", enrollable_id: @contact.id
      ).pluck(:id)
      delivery_ids = SequenceDelivery.where(sequence_enrollment_id: enrollment_ids).pluck(:id)
      email_ids = Message.with_deleted.where(id: message_ids).where.not(email_message_id: nil)
                         .pluck(:email_message_id)
      inbound_ids = ActionMailbox::InboundEmail.where(message_id: email_ids).pluck(:id)
      {
        "Contact" => [ @contact.id ], "Case" => case_ids, "Message" => message_ids,
        "Deal" => deal_ids, "Lead" => lead_ids, "WorkItem" => work_item_ids,
        "WorkComment" => comment_ids, "Notification" => notification_ids,
        "SequenceEnrollment" => enrollment_ids, "SequenceDelivery" => delivery_ids,
        "ActionMailbox::InboundEmail" => inbound_ids
      }
    end

    def redact_audit_entries!(graph, identifiers)
      relation = nil
      graph.each do |type, ids|
        next if ids.empty?

        candidate = AuditEntry.where(auditable_type: type, auditable_id: ids)
        relation = relation ? relation.or(candidate) : candidate
      end
      actor_entries = AuditEntry.where(actor_type: "Contact", actor_id: @contact.id)
      relation = relation ? relation.or(actor_entries) : actor_entries
      content_ids = AuditEntry.where(tenant_id: @tenant.id).select do |entry|
        [ entry.changeset, entry.metadata ].compact.any? do |value|
          serialized = JSON.generate(value)
          identifiers.any? { |identifier| serialized.include?(identifier) }
        end
      end.map(&:id)
      relation = relation.or(AuditEntry.where(id: content_ids)) if content_ids.any?
      AuditRedactor.call(entries: relation, subject_token: @token)
    end

    def redact_domain_records!(graph, identifiers)
      @contact.update_columns(
        name: "Erased contact #{@token.first(8)}", email: nil, phone: nil,
        external_id: "erased-#{@token}", notes: nil, sms_consent: false,
        organisation_id: nil, source_connector_id: nil, erased_at: Time.current,
        erasure_token: @token, deleted_at: Time.current
      )
      Case.with_deleted.where(id: graph.fetch("Case")).find_each do |kase|
        kase.update_columns(subject: "Erased request #{kase.tracking_id}", description: nil,
                            external_id: nil)
      end
      Message.with_deleted.where(id: graph.fetch("Message")).update_all(
        body: "[Erased for privacy]", subject: nil, metadata: nil,
        email_message_id: nil, external_message_id: nil, source_author_name: nil,
        author_type: nil, author_id: nil
      )
      Deal.with_deleted.where(id: graph.fetch("Deal")).find_each do |deal|
        deal.update_columns(name: "Erased opportunity #{deal.id}", external_id: nil, labels: nil)
      end
      Lead.with_deleted.where(id: graph.fetch("Lead")).find_each do |lead|
        lead.update_columns(name: "Erased lead #{lead.id}", email: nil, phone: nil,
                            company_name: nil, notes: nil, external_id: nil, labels: nil)
      end
      WorkItem.with_deleted.where(id: graph.fetch("WorkItem")).find_each do |item|
        item.update_columns(title: "Erased linked work #{item.reference}", description: nil)
      end
      WorkComment.with_deleted.where(id: graph.fetch("WorkComment")).update_all(
        body: "[Erased for privacy]", source_author_name: "Erased source"
      )
      Notification.where(id: graph.fetch("Notification")).update_all(
        title: "Linked request changed", body: "A privacy erasure was completed", metadata: {}
      )
      Decision.where(subject_type: "Case", subject_id: graph.fetch("Case"))
              .update_all(subject_label: "Erased request", action_params: {})
      SequenceEnrollment.with_deleted.where(id: graph.fetch("SequenceEnrollment"))
                        .update_all(status: SequenceEnrollment.statuses.fetch("cancelled"), next_run_at: nil)
      SequenceDelivery.where(id: graph.fetch("SequenceDelivery"))
                      .update_all(recipient: nil, payload: {}, tracking_token: nil,
                                  last_error: "recipient erased")
      SecurityEvent.where(tenant_id: @tenant.id).where(email: identifiers).update_all(
        email: nil, metadata: nil, ip_address: nil, user_agent: nil
      )
    end

    def remove_attachments!(graph)
      message_ids = graph.fetch("Message")
      inbound_ids = graph.fetch("ActionMailbox::InboundEmail")
      pairs = {
        "Case" => graph.fetch("Case"), "Message" => message_ids,
        "WorkItem" => graph.fetch("WorkItem"), "ActionMailbox::InboundEmail" => inbound_ids
      }
      attachments = pairs.flat_map do |type, ids|
        ActiveStorage::Attachment.where(record_type: type, record_id: ids).to_a
      end
      attachment_ids = attachments.map(&:id)
      blobs = attachments.map(&:blob).uniq
      exclusive = blobs.select { |blob| blob.attachments.where.not(id: attachment_ids).none? }
      deletion_ids = exclusive.map do |blob|
        StorageDeletion.create!(owner_tenant_id: @tenant.id, service_name: blob.service_name,
                                blob_key: blob.key).id
      end
      ActiveStorage::Attachment.where(id: attachment_ids).delete_all
      ActiveStorage::VariantRecord.where(blob_id: exclusive.map(&:id)).delete_all
      ActiveStorage::Blob.where(id: exclusive.map(&:id)).delete_all
      ActionMailbox::InboundEmail.where(id: inbound_ids).delete_all
      deletion_ids
    end
  end
end
