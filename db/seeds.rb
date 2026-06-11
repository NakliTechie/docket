# Idempotent base seeds: a break-glass admin account and sensible
# defaults. Rich demo data ships separately (db/seeds/demo.rb, G4).
#
# The admin password comes from DOCKET_ADMIN_PASSWORD. If unset, we
# generate a random one and print it ONCE on creation — never ship a
# known default (this is a public repo). The password is only applied
# when the account is first created, so re-running seeds never resets it.
admin_password = ENV["DOCKET_ADMIN_PASSWORD"].presence || SecureRandom.alphanumeric(24)
admin_created = false

admin = User.find_or_create_by!(email_address: "admin@docket.local") do |user|
  user.name = "Docket Admin"
  user.role = :admin
  user.password = admin_password
  admin_created = true
end

if admin_created
  puts "Seeded break-glass admin: #{admin.email_address}"
  if ENV["DOCKET_ADMIN_PASSWORD"].blank?
    puts "  Generated password (shown once — change it after first login): #{admin_password}"
  end
end
