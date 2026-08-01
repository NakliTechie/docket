# Append-only, hash-chained audit log (handoff §6). Each entry stores
# sha256(previous_sha + canonical_entry_json); the chain is verified
# end-to-end by `bin/rails audit:verify`.
class AuditEntry < ApplicationRecord
  # A platform super-admin provisioning or maintaining another tenant remains
  # the truthful actor on that tenant's audit entry. Attribution can cross the
  # ownership boundary; the auditable business record cannot.
  allows_cross_tenant_association :actor
  GENESIS_SHA = ("0" * 64).freeze
  CHAIN_LOCK_KEY = 0x0D0C4E7 # arbitrary, stable advisory-lock key

  # The actor is always a User or ServiceAccount (both SoftDeletable), so
  # with_deleted keeps a soft-deleted actor's name in the history instead
  # of rendering "deleted_user". auditable is intentionally NOT scoped:
  # it can point at non-SoftDeletable models (Setting, SlaTarget, …) whose
  # classes have no with_deleted scope.
  belongs_to :actor, -> { with_deleted }, polymorphic: true, optional: true
  # optional: the reference is validated by column presence below, NOT by
  # loading the object. A destroy audit is appended while its auditable is
  # soft-deleted (default scope hides it) and/or marked_for_destruction during
  # nested autosave — a required belongs_to rejects both as "must exist" and
  # would 500 the very destruction it is recording. The id+type are what the
  # hash chain records anyway; the loaded object never enters canonical_json.
  belongs_to :auditable, polymorphic: true, optional: true
  validates :auditable_type, :auditable_id, presence: true
  # The chain itself stays GLOBAL (AuditEntry is deliberately NOT acts_as_tenant):
  # tenant_id is a denormalized filter column for per-tenant audit views only. It
  # is NEVER part of canonical_json — adding it would re-hash every entry and
  # break verify_chain. Nullable (pre-tenancy + global-auditable entries).
  belongs_to :tenant, optional: true
  belongs_to :redaction_event, class_name: "AuditEntry", optional: true

  validates :action, :previous_sha, :sha, presence: true

  after_commit :persist_external_checkpoint, on: :create, if: -> { AuditCheckpoint.enabled? }

  # The hash-chain is global, but the per-tenant audit/activity READ surfaces
  # must not cross tenants in shared mode (C1). super_admin — the cross-tenant
  # platform tier — sees the whole chain; an isolated deployment has one tenant
  # so the filter is a no-op; everyone else sees only their tenant's entries.
  def self.global_view?(user)
    Tenant.isolated_deployment? || !!user&.role_super_admin?
  end

  def self.visible_to(user)
    global_view?(user) ? all : where(tenant_id: ActsAsTenant.current_tenant&.id)
  end

  # Append-only: no updates, no deletes — at the model layer too.
  def readonly?
    persisted?
  end

  before_destroy { raise ActiveRecord::ReadOnlyRecord, "audit entries are append-only" }

  def self.append!(action:, auditable:, changeset: nil, metadata: nil, actor: Current.effective_actor)
    with_chain_lock do
      entry = new(
        action: action,
        auditable: auditable,
        actor: actor,
        tenant_id: ActsAsTenant.current_tenant&.id, # filter-only; not in canonical_json
        changeset: changeset,
        metadata: metadata.presence,
        previous_sha: order(id: :desc).limit(1).pick(:sha) || GENESIS_SHA,
        created_at: Time.current.utc
      )
      entry.sha = entry.compute_sha
      entry.save!
      entry
    end
  end

  # Serialises writers so the chain never forks. Postgres needs an advisory
  # lock; SQLite writes are already serialised by the single-writer model.
  def self.with_chain_lock(&block)
    transaction do
      if connection.adapter_name.match?(/postgresql/i)
        connection.execute("SELECT pg_advisory_xact_lock(#{CHAIN_LOCK_KEY})")
      end
      yield
    end
  end

  def compute_sha
    Digest::SHA256.hexdigest(previous_sha + canonical_json)
  end

  # Canonical form: fixed field order, recursively key-sorted JSON values,
  # microsecond UTC timestamps — identical at write and verify time.
  def canonical_json
    JSON.generate([
      action,
      auditable_type, auditable_id,
      actor_type, actor_id,
      self.class.canonicalize(changeset),
      self.class.canonicalize(metadata),
      created_at.utc.iso8601(6)
    ])
  end

  def self.canonicalize(value)
    case value
    when Hash  then value.sort_by { |k, _| k.to_s }.to_h { |k, v| [ k.to_s, canonicalize(v) ] }
    when Array then value.map { |v| canonicalize(v) }
    else value
    end
  end

  # Walks the whole chain; returns { ok: true, count: } or the first break:
  # { ok: false, entry_id:, expected_sha:, stored_sha:, reason: }.
  VERIFICATION_CACHE_KEY = "audit_chain_verification".freeze
  VERIFICATION_CACHE_TTL = 1.minute

  # Cached by default: the full walk is O(n) over the whole table, so the
  # admin status page and the API endpoint would otherwise re-verify the
  # entire chain on every hit (a slow path / DoS lever for anyone with
  # audit:read). The TTL bounds repeated full walks to once per window;
  # tampering is still detected, within at most one TTL of latency. Pass
  # cache: false (the CLI does) for a guaranteed-fresh full check, which
  # also refreshes the cache the web surfaces read.
  def self.verify_chain(cache: true, checkpoint: AuditCheckpoint.enabled?)
    return refresh_verification_cache(checkpoint: checkpoint) unless cache
    Rails.cache.fetch("#{VERIFICATION_CACHE_KEY}:#{checkpoint}", expires_in: VERIFICATION_CACHE_TTL) do
      verify_checkpoint(compute_chain_verification, checkpoint: checkpoint)
    end
  end

  def self.refresh_verification_cache(checkpoint: AuditCheckpoint.enabled?)
    verify_checkpoint(compute_chain_verification, checkpoint: checkpoint).tap do |result|
      Rails.cache.write("#{VERIFICATION_CACHE_KEY}:#{checkpoint}", result,
                        expires_in: VERIFICATION_CACHE_TTL)
    end
  end

  def self.verify_checkpoint(result, checkpoint:)
    checkpoint && result[:ok] ? AuditCheckpoint.compare(result) : result.except(:head_id, :head_sha)
  end

  def self.compute_chain_verification
    redaction_proofs = redaction_proofs_by_entry_id
    previous = GENESIS_SHA
    count = 0
    find_each(cursor: :id, order: :asc) do |entry|
      if entry.previous_sha != previous
        return { ok: false, entry_id: entry.id, reason: "previous_sha mismatch",
                 expected_sha: previous, stored_sha: entry.previous_sha }
      end
      if entry.redacted_at?
        proof = redaction_proofs[entry.id]
        unless proof && proof[:sha] == entry.sha && proof[:event_id] == entry.redaction_event_id &&
               proof[:event_id] > entry.id
          return { ok: false, entry_id: entry.id, reason: "invalid redaction proof",
                   expected_sha: entry.sha, stored_sha: proof&.dig(:sha) }
        end
      elsif entry.compute_sha != entry.sha
        return { ok: false, entry_id: entry.id, reason: "entry hash mismatch",
                 expected_sha: entry.compute_sha, stored_sha: entry.sha }
      end
      previous = entry.sha
      count += 1
    end
    head = order(id: :desc).limit(1).pick(:id, :sha)
    { ok: true, count: count, head_id: head&.first, head_sha: head&.last || GENESIS_SHA }
  end

  def self.redaction_proofs_by_entry_id
    ids = where.not(redaction_event_id: nil).distinct.pluck(:redaction_event_id)
    where(id: ids, action: "privacy.audit_redacted").each_with_object({}) do |event, proofs|
      Array(event.metadata&.dig("entries")).each do |proof|
        proofs[proof.fetch("id").to_i] = { sha: proof.fetch("sha"), event_id: event.id }
      end
    end
  end
  private_class_method :redaction_proofs_by_entry_id


  private

  def persist_external_checkpoint
    AuditCheckpoint.persist_current!
  rescue AuditCheckpoint::Error, SystemCallError => e
    Rails.logger.error("Audit checkpoint could not advance: #{e.class}: #{e.message}")
  end
end
