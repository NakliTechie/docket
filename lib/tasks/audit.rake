namespace :audit do
  desc "Verify the audit log hash chain end-to-end; reports the first break"
  task verify: :environment do
    result = AuditEntry.verify_chain
    if result[:ok]
      puts "PASS: audit chain intact (#{result[:count]} entries)"
    else
      puts "FAIL: audit chain broken at entry ##{result[:entry_id]} (#{result[:reason]})"
      puts "  expected: #{result[:expected_sha]}"
      puts "  stored:   #{result[:stored_sha]}"
      exit 1
    end
  end
end
