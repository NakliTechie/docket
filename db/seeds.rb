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

# Minimal ticketing floor, so a fresh deploy can take tickets on day one —
# not just deals. These only fire on a truly empty install (.none?): they
# never override an operator who has already set up their own queues/SLA,
# and re-running seeds is a no-op. Categories are intentionally left empty
# (opt-in, OFF by default). Rich per-scenario setup ships in db/seeds/demo.rb.
if defined?(CaseQueue) && CaseQueue.none?
  queue = CaseQueue.create!(name: "General", description: "Default queue for incoming requests.")
  Setting.set("default_queue_id", queue.id)
  puts "Seeded default queue: #{queue.name} (set as default)"
end

if defined?(SlaPolicy) && SlaPolicy.none?
  sla = SlaPolicy.create!(name: "Standard", description: "Default first-response and resolution targets.")
  # [priority, first_response_minutes, resolution_minutes] — 8h/7d down to 30m/8h.
  [ [ :low, 480, 10080 ], [ :normal, 240, 4320 ], [ :high, 60, 1440 ], [ :urgent, 30, 480 ] ].each do |priority, fr, res|
    sla.sla_targets.create!(priority: priority, first_response_minutes: fr, resolution_minutes: res)
  end
  Setting.set("default_sla_policy_id", sla.id)
  puts "Seeded default SLA policy: #{sla.name} (#{sla.sla_targets.size} targets, set as default)"
end
