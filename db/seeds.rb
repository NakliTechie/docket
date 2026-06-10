# Idempotent base seeds: a break-glass admin account and sensible
# defaults. Rich demo data ships separately (db/seeds/demo.rb, G4).
admin = User.find_or_create_by!(email_address: "admin@docket.local") do |user|
  user.name = "Docket Admin"
  user.role = :admin
  user.password = ENV.fetch("DOCKET_ADMIN_PASSWORD", "docketadmin")
end

puts "Seeded admin: #{admin.email_address}"
