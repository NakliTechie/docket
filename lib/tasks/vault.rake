namespace :vault do
  desc "Show the active and readable vault-key versions (never key material)"
  task status: :environment do
    status = Docket::VaultKeyring.current.status
    puts "Active vault key: #{status[:active]}"
    puts "Readable versions: #{status[:readable_versions].join(', ')}"
  end

  desc "Re-encrypt every encrypted attribute with the active vault key"
  task reencrypt: :environment do
    active = Docket::VaultKeyring.current.active_version
    unless ENV["CONFIRM_VAULT_REENCRYPT"] == active
      abort "Refusing: set CONFIRM_VAULT_REENCRYPT=#{active} (or DRY_RUN=true)"
    end unless ENV["DRY_RUN"] == "true"

    result = Vault::Reencrypt.call(dry_run: ENV["DRY_RUN"] == "true")
    puts "#{ENV['DRY_RUN'] == 'true' ? 'Would re-encrypt' : 'Re-encrypted'} " \
         "#{result.attributes} attributes on #{result.records} records."
    if result.errors.any?
      result.errors.each { |error| warn "#{error[:model]}##{error[:id]}: #{error[:error]}" }
      abort "Vault re-encryption failed for #{result.errors.size} records"
    end
  end
end
