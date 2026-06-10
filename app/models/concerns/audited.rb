# Appends a hash-chained AuditEntry on every mutation (handoff §6).
# Actor resolution: an explicitly set Current.actor (service account,
# portal contact) wins over the signed-in staff user.
module Audited
  extend ActiveSupport::Concern

  AUDIT_IGNORED_ATTRIBUTES = %w[updated_at].freeze

  included do
    after_create  { append_audit_entry("create") }
    after_update  { append_audit_entry(audit_action_for_update) if audited_changes.present? }
    after_destroy { append_audit_entry("delete") }
  end

  private

  def append_audit_entry(verb)
    AuditEntry.append!(
      action: "#{model_name.param_key}.#{verb}",
      auditable: self,
      changeset: audited_changes,
      metadata: Current.audit_metadata
    )
  end

  def audit_action_for_update
    saved_change_to_attribute?(:deleted_at) && deleted_at.present? ? "delete" : "update"
  end

  # { attribute => [before, after] }, minus noise and secrets.
  def audited_changes
    changes = saved_changes.except(*AUDIT_IGNORED_ATTRIBUTES, *audit_redacted_attributes)
    audit_redacted_attributes.each do |attr|
      changes[attr] = [ "[REDACTED]", "[REDACTED]" ] if saved_change_to_attribute?(attr)
    end
    changes
  end

  # Override per model for attributes whose values must never enter the audit log.
  def audit_redacted_attributes
    self.class.attribute_names & %w[password_digest]
  end
end
