# One agent-initiated action through a connector — the outbound mirror of
# ConnectorRun. Audited: its proposed→approved→executing→succeeded
# transitions hash-chain themselves, so the approval gate is tamper-evident
# for free. args/result may carry PII or secrets and are redacted from the
# chain (who/what/for-whom stays; the payload does not).
class ConnectorInvocation < ApplicationRecord
  include Audited

  belongs_to :connector
  belongs_to :requested_by, polymorphic: true, optional: true
  belongs_to :approved_by, class_name: "User", optional: true

  enum :status, { proposed: 0, approved: 1, rejected: 2,
                  executing: 3, succeeded: 4, failed: 5 }, prefix: true

  validates :action, presence: true
  validates :idempotency_key, uniqueness: { scope: :connector_id }, allow_nil: true

  before_create :mint_delegation_id

  scope :recent_first, -> { order(id: :desc) }

  def duration_seconds
    return nil unless created_at && finished_at
    (finished_at - created_at).round(1)
  end

  def awaiting_approval?
    status_proposed?
  end

  # ServiceAccount (an agent) or a staff User — both respond to #name.
  def requester_label
    requested_by&.name
  end

  def audit_redacted_attributes
    super | %w[args result]
  end

  private

  # Opaque, stable, bound to this invocation (and thus its principal) at
  # creation — the correlation id propagated downstream and into the audit.
  def mint_delegation_id
    self.delegation_id ||= "dlg_#{SecureRandom.alphanumeric(24)}"
  end
end
