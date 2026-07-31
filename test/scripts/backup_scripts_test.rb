require "test_helper"

# bin/backup and bin/restore are the difference between a disk failure being an
# afternoon and being the end of the customer relationship. They cannot be
# exercised end to end without a Postgres host (that drill is an operator task),
# so this asserts the contract they must honour — which is where the README's
# one-liner went wrong: it dumped one database out of four and no attachments.
class BackupScriptsTest < ActiveSupport::TestCase
  BACKUP = Rails.root.join("bin/backup")
  RESTORE = Rails.root.join("bin/restore")

  test "both scripts exist, are executable, and are valid shell" do
    [ BACKUP, RESTORE ].each do |script|
      assert File.exist?(script), "#{script.basename} is missing"
      assert File.executable?(script), "#{script.basename} is not executable"
      assert system("bash", "-n", script.to_s, out: File::NULL, err: File::NULL),
             "#{script.basename} is not valid shell"
    end
  end

  test "the backup covers every database in config/database.yml, not just the primary" do
    body = File.read(BACKUP)
    # Render ERB first, the way Rails loads database.yml — the `test:` block now
    # branches on DATABASE_URL (Postgres CI leg vs SQLite), which a raw YAML read
    # can't parse. Only `production` is asserted on here, and ERB leaves its keys
    # untouched.
    rendered = ERB.new(File.read(Rails.root.join("config/database.yml"))).result
    configured = YAML.load(rendered, aliases: true).fetch("production").keys

    assert_equal %w[cable cache primary queue], configured.sort,
                 "database.yml changed — the backup script must be updated to match"
    configured.each do |name|
      if name == "primary"
        assert_match(/AuditCheckpoint\.capture_backup!/, body, "primary database is not backed up")
      else
        assert_match(/dump #{name}\b/, body, "#{name} database is not backed up")
      end
    end
  end

  test "attachments are backed up — they do not live in Postgres" do
    assert_match(/tar -czf .*storage/, File.read(BACKUP))
    assert_match(/tar -xzf .*storage/, File.read(RESTORE))
  end

  # H19: attachments live only on disk, so a backup that omits them is a trap.
  test "the backup exits non-zero when the storage directory is missing" do
    body = File.read(BACKUP)
    assert_match(/no storage directory[^\n]*\n\s*exit 1/, body,
                 "missing storage must `exit 1`, not warn-and-continue")
  end

  # H20: sibling DB URLs are derived before any ?query (not concatenated onto the
  # whole URL), and the script runs from the app root so a relative storage path
  # resolves wherever it's invoked from.
  test "backup and restore derive sibling URLs safely and backup runs from the app root" do
    [ BACKUP, RESTORE ].each do |script|
      body = File.read(script)
      assert_match(/sibling_url/, body, "#{script.basename} must parse sibling URLs")
      assert_no_match(/\$\{DATABASE_URL\}_cache/, body,
                      "#{script.basename} must not concatenate onto the whole URL")
    end
    assert_match(%r{cd "\$\(dirname "\$0"\)/\.\."}, File.read(BACKUP),
                 "backup must cd to the app root")
  end

  test "a partial failure fails the whole backup" do
    assert_match(/set -euo pipefail/, File.read(BACKUP),
                 "a backup that half-worked must not report success")
  end

  test "backup bytes are private and restore authenticates them before overwrite" do
    backup = File.read(BACKUP)
    restore = File.read(RESTORE)

    assert_match(/umask 077/, backup)
    assert_match(/DOCKET_BACKUP_SIGNING_KEY/, backup)
    assert_match(/SHA256SUMS\.hmac/, backup)
    assert_match(/fixed_length_secure_compare/, restore)
    assert_operator restore.index("fixed_length_secure_compare"), :<, restore.index("load primary")
  end

  test "restore refuses to run without explicit confirmation" do
    assert_match(/DOCKET_RESTORE_CONFIRM/, File.read(RESTORE),
                 "restore overwrites live databases; it must not be a single keystroke")
  end

  test "restore ends by verifying the audit chain" do
    assert_match(/audit:verify/, File.read(RESTORE),
                 "a partial or tampered restore must be DETECTED, not assumed")
  end

  test "restore validates every dump and attachments before mutating a database" do
    body = File.read(RESTORE)
    preflight = body.index("for name in primary cache queue cable")
    first_restore = body.index("load primary")

    assert preflight, "all four dumps need a preflight loop"
    assert_match(/pg_restore --list/, body, "existence alone does not prove a dump is readable")
    assert_match(/tar -tzf/, body, "the attachment archive must be readable before restore")
    assert_match(/audit_checkpoint\.json/, body, "restore must require the external audit anchor")
    assert_operator preflight, :<, first_restore, "preflight must finish before primary is overwritten"
  end

  test "primary dump and external audit checkpoint are captured under one chain lock" do
    body = File.read(BACKUP)

    assert_match(/AuditCheckpoint\.capture_backup!/, body)
    assert_match(/audit_checkpoint: present/, body)
  end
end
