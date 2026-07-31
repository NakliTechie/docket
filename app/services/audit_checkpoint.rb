require "fileutils"
require "json"

# A durable anchor for the hash chain that does not live in audit_entries.
# Without it, deleting the tail (or the whole table) leaves a perfectly valid
# shorter chain. The checkpoint travels with attachment storage and a frozen
# copy travels with every backup.
class AuditCheckpoint
  VERSION = 1
  GENESIS = AuditEntry::GENESIS_SHA

  class Error < StandardError; end
  class Missing < Error; end
  class Mismatch < Error; end

  class << self
    def enabled?
      ENV["DOCKET_AUDIT_CHECKPOINT"] == "true" || Rails.env.production?
    end

    def path
      Pathname.new(
        ENV.fetch("DOCKET_AUDIT_CHECKPOINT_PATH", Rails.root.join("storage/audit_checkpoint.json"))
      )
    end

    def read(checkpoint_path: path)
      return nil unless checkpoint_path.exist?

      validate_payload!(JSON.parse(checkpoint_path.read))
    rescue JSON::ParserError => e
      raise Mismatch, "audit checkpoint is not valid JSON: #{e.message}"
    end

    # Called after every committed AuditEntry. Existing anchors are only moved
    # forward: if their previous head disappeared or changed, the suspicious
    # state is retained for audit:verify instead of blessing the shorter chain.
    def persist_current!(allow_initialize: false)
      synchronize do
        payload = advance_payload(allow_initialize: allow_initialize)
        write_payload(path, payload)
        payload
      end
    end

    def initialize!
      synchronize do
        raise Error, "audit checkpoint already exists at #{path}" if path.exist?

        payload = current_payload
        write_payload(path, payload)
        payload
      end
    end

    # Freeze audited writes while pg_dump takes its MVCC snapshot. This makes
    # the bundled checkpoint and primary dump describe the exact same chain;
    # a checkpoint copied before or after an unlocked dump can race an append.
    def capture_backup!(dump_path:, checkpoint_path:)
      synchronize do
        payload = advance_payload(allow_initialize: false)
        write_payload(path, payload)

        verification = AuditEntry.compute_chain_verification
        verified = compare(verification, payload)
        raise Mismatch, verified[:reason] unless verified[:ok]

        ok = system(
          "pg_dump", "--format=custom", "--no-owner", "--no-acl",
          "--file=#{dump_path}", ENV.fetch("DATABASE_URL")
        )
        raise Error, "pg_dump failed for the primary database" unless ok

        write_payload(Pathname.new(checkpoint_path), payload)
        payload
      end
    end

    def compare(verification, checkpoint = read)
      return verification unless verification[:ok]
      return missing_result(verification) if checkpoint.nil?

      if checkpoint["count"] == verification[:count] &&
          checkpoint["head_sha"] == verification[:head_sha] &&
          checkpoint["head_id"] == verification[:head_id]
        public_result(verification)
      else
        {
          ok: false,
          entry_id: verification[:head_id],
          reason: "external audit checkpoint mismatch",
          expected_sha: checkpoint["head_sha"],
          stored_sha: verification[:head_sha],
          expected_count: checkpoint["count"],
          count: verification[:count]
        }
      end
    rescue Error => e
      {
        ok: false,
        entry_id: verification[:head_id],
        reason: e.message,
        expected_sha: nil,
        stored_sha: verification[:head_sha],
        count: verification[:count]
      }
    end

    private

    def synchronize(&block)
      FileUtils.mkdir_p(path.dirname)
      File.open("#{path}.lock", File::RDWR | File::CREAT, 0o600) do |lock|
        lock.flock(File::LOCK_EX)
        AuditEntry.with_chain_lock(&block)
      end
    end

    def advance_payload(allow_initialize:)
      checkpoint = read
      if checkpoint.nil?
        count = AuditEntry.count
        if count > 1 && !allow_initialize
          raise Missing,
                "external audit checkpoint is missing; inspect the chain, then run " \
                "DOCKET_AUDIT_CHECKPOINT_CONFIRM=yes bin/rails audit:checkpoint:init"
        end
        return current_payload(count: count)
      end

      if checkpoint["count"].positive?
        anchored_sha = AuditEntry.where(id: checkpoint["head_id"]).pick(:sha)
        unless anchored_sha == checkpoint["head_sha"]
          raise Mismatch, "external audit checkpoint head is absent or changed"
        end
      end

      delta = if checkpoint["head_id"]
        AuditEntry.where("id > ?", checkpoint["head_id"]).count
      else
        AuditEntry.count
      end
      current_payload(count: checkpoint["count"] + delta)
    end

    def current_payload(count: AuditEntry.count)
      head_id, head_sha = AuditEntry.order(id: :desc).limit(1).pick(:id, :sha)
      {
        "version" => VERSION,
        "count" => count,
        "head_id" => head_id,
        "head_sha" => head_sha || GENESIS,
        "updated_at" => Time.current.utc.iso8601(6)
      }
    end

    def validate_payload!(payload)
      unless payload.is_a?(Hash) && payload["version"] == VERSION &&
          payload["count"].is_a?(Integer) && payload["count"] >= 0 &&
          payload["head_sha"].to_s.match?(/\A[0-9a-f]{64}\z/) &&
          (payload["head_id"].nil? || payload["head_id"].is_a?(Integer))
        raise Mismatch, "audit checkpoint has an invalid schema"
      end
      payload
    end

    def write_payload(target, payload)
      FileUtils.mkdir_p(target.dirname)
      temporary = target.dirname.join(".#{target.basename}.#{Process.pid}.tmp")
      File.open(temporary, "w", 0o600) do |file|
        file.write(JSON.generate(payload))
        file.write("\n")
        file.flush
        file.fsync
      end
      File.rename(temporary, target)
      File.chmod(0o600, target)
    ensure
      FileUtils.rm_f(temporary) if defined?(temporary)
    end

    def missing_result(verification)
      return public_result(verification) if verification[:count].zero?

      {
        ok: false,
        entry_id: verification[:head_id],
        reason: "external audit checkpoint missing",
        expected_sha: nil,
        stored_sha: verification[:head_sha],
        count: verification[:count]
      }
    end

    def public_result(verification)
      { ok: true, count: verification[:count] }
    end
  end
end
