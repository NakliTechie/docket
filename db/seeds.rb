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

# Default sales pipeline (v1.2 CRM) so deals have somewhere to land.
if defined?(Pipeline) && Pipeline.none?
  pipeline = Pipeline.new(name: "Sales", slug: "sales", position: 0)
  pipeline.pipeline_stages.build([
    { name: "New", position: 0, probability: 10 },
    { name: "Contacted", position: 1, probability: 25 },
    { name: "Qualified", position: 2, probability: 50 },
    { name: "Proposal", position: 3, probability: 75 },
    { name: "Won", position: 4, probability: 100, is_won: true },
    { name: "Lost", position: 5, probability: 0, is_lost: true }
  ])
  pipeline.save!
  puts "Seeded default pipeline: #{pipeline.name} (#{pipeline.pipeline_stages.size} stages)"
end
