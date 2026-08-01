namespace :audit do
  desc "Verify the audit log hash chain end-to-end; reports the first break"
  task verify: :environment do
    result = AuditEntry.verify_chain(cache: false, checkpoint: true)
    if result[:ok]
      puts "PASS: audit chain intact (#{result[:count]} entries)"
    else
      puts "FAIL: audit chain broken at entry ##{result[:entry_id]} (#{result[:reason]})"
      puts "  expected: #{result[:expected_sha]}"
      puts "  stored:   #{result[:stored_sha]}"
      exit 1
    end
  end


  namespace :checkpoint do
    desc "Initialize the external audit anchor after manually inspecting a legacy chain"
    task init: :environment do
      unless ENV["DOCKET_AUDIT_CHECKPOINT_CONFIRM"] == "yes"
        warn "Refusing to bless the current chain without DOCKET_AUDIT_CHECKPOINT_CONFIRM=yes"
        exit 65
      end

      chain = AuditEntry.verify_chain(cache: false, checkpoint: false)
      abort "Audit chain is already broken: #{chain.inspect}" unless chain[:ok]

      checkpoint = AuditCheckpoint.initialize!
      puts "PASS: external audit checkpoint initialized (#{checkpoint['count']} entries)"
    end
  end
end
