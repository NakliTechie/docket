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
    configured = YAML.load_file(Rails.root.join("config/database.yml"), aliases: true)
                     .fetch("production").keys

    assert_equal %w[cable cache primary queue], configured.sort,
                 "database.yml changed — the backup script must be updated to match"
    configured.each do |name|
      assert_match(/dump #{name}\b/, body, "#{name} database is not backed up")
    end
  end

  test "attachments are backed up — they do not live in Postgres" do
    assert_match(/tar -czf .*storage/, File.read(BACKUP))
    assert_match(/tar -xzf .*storage/, File.read(RESTORE))
  end

  test "a partial failure fails the whole backup" do
    assert_match(/set -euo pipefail/, File.read(BACKUP),
                 "a backup that half-worked must not report success")
  end

  test "restore refuses to run without explicit confirmation" do
    assert_match(/DOCKET_RESTORE_CONFIRM/, File.read(RESTORE),
                 "restore overwrites live databases; it must not be a single keystroke")
  end

  test "restore ends by verifying the audit chain" do
    assert_match(/audit:verify/, File.read(RESTORE),
                 "a partial or tampered restore must be DETECTED, not assumed")
  end
end
