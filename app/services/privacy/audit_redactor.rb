module Privacy
  class AuditRedactor
    BATCH_SIZE = 500

    def self.call(...) = new(...).call

    def initialize(entries:, subject_token:, reason: "privacy_erasure")
      @entries = entries
      @subject_token = subject_token
      @reason = reason
    end

    def call
      ids = @entries.where(redacted_at: nil).where.not(action: "privacy.audit_redacted")
                    .order(:id).pluck(:id, :sha)
      ids.each_slice(BATCH_SIZE).map do |batch|
        event = AuditEntry.append!(
          action: "privacy.audit_redacted", auditable: redaction_auditable,
          changeset: nil,
          metadata: {
            reason: @reason, subject_token: Digest::SHA256.hexdigest(@subject_token.to_s),
            entries: batch.map { |id, sha| { id: id, sha: sha } }
          },
          actor: Current.effective_actor
        )
        AuditEntry.where(id: batch.map(&:first)).update_all(
          changeset: nil, metadata: nil, actor_type: nil, actor_id: nil,
          redacted_at: Time.current, redaction_event_id: event.id
        )
        event
      end
    end

    private

    def redaction_auditable
      @entries.first&.auditable || ActsAsTenant.current_tenant || Tenant.primary
    end
  end
end
