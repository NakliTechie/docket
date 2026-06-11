# Append-only, hash-chained audit log (handoff §6). Each entry stores
# sha256(previous_sha + canonical_entry_json); the chain is verified
# end-to-end by `bin/rails audit:verify`.
class AuditEntry < ApplicationRecord
  GENESIS_SHA = ("0" * 64).freeze
  CHAIN_LOCK_KEY = 0x0D0C4E7 # arbitrary, stable advisory-lock key

  # The actor is always a User or ServiceAccount (both SoftDeletable), so
  # with_deleted keeps a soft-deleted actor's name in the history instead
  # of rendering "deleted_user". auditable is intentionally NOT scoped:
  # it can point at non-SoftDeletable models (Setting, SlaTarget, …) whose
  # classes have no with_deleted scope.
  belongs_to :actor, -> { with_deleted }, polymorphic: true, optional: true
  belongs_to :auditable, polymorphic: true

  validates :action, :previous_sha, :sha, presence: true

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
  def self.verify_chain(cache: true)
    return refresh_verification_cache unless cache
    Rails.cache.fetch(VERIFICATION_CACHE_KEY, expires_in: VERIFICATION_CACHE_TTL) do
      compute_chain_verification
    end
  end

  def self.refresh_verification_cache
    compute_chain_verification.tap do |result|
      Rails.cache.write(VERIFICATION_CACHE_KEY, result, expires_in: VERIFICATION_CACHE_TTL)
    end
  end

  def self.compute_chain_verification
    previous = GENESIS_SHA
    count = 0
    order(:id).find_each do |entry|
      if entry.previous_sha != previous
        return { ok: false, entry_id: entry.id, reason: "previous_sha mismatch",
                 expected_sha: previous, stored_sha: entry.previous_sha }
      end
      recomputed = entry.compute_sha
      if recomputed != entry.sha
        return { ok: false, entry_id: entry.id, reason: "entry hash mismatch",
                 expected_sha: recomputed, stored_sha: entry.sha }
      end
      previous = entry.sha
      count += 1
    end
    { ok: true, count: count }
  end
end
