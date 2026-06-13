namespace :tenants do
  desc "Provision a tenant (shared mode). " \
       "Usage: NAME='Acme' SUBDOMAIN=acme [ADMIN_EMAIL=boss@acme.com] bin/rails tenants:provision"
  task provision: :environment do
    result = Tenants::Provisioner.call(
      name: ENV.fetch("NAME"),
      subdomain: ENV.fetch("SUBDOMAIN"),
      admin_email: ENV["ADMIN_EMAIL"].presence
    )
    puts "Provisioned tenant '#{result.tenant.name}' (subdomain: #{result.tenant.subdomain})"
    if result.admin_password
      puts "  admin: #{result.admin.email_address}"
      puts "  password (shown once — change after first login): #{result.admin_password}"
    end
  end
end
