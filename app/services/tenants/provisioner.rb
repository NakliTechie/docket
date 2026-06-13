module Tenants
  # Creates a tenant and seeds its day-one floor — the entry point for SHARED-mode
  # provisioning (the super_admin platform console and the provision rake task).
  # Isolated deploys don't use this; they get the primary tenant from db/seeds.rb.
  #
  # The tenant's first admin is a CLIENT_ADMIN (the per-tenant org admin), never a
  # super_admin (that platform tier sits above tenants). Returns the tenant and,
  # when an admin was created, the generated one-time password.
  class Provisioner
    Result = Struct.new(:tenant, :admin, :admin_password, keyword_init: true)

    def self.call(...) = new(...).call

    def initialize(name:, subdomain:, admin_email: nil, admin_name: nil)
      @name = name
      @subdomain = subdomain.to_s.strip.downcase.presence
      @admin_email = admin_email.to_s.strip.downcase.presence
      @admin_name = admin_name
    end

    def call
      tenant = Tenant.create!(name: @name, subdomain: @subdomain, slug: @subdomain)
      admin = nil
      password = nil

      ActsAsTenant.with_tenant(tenant) do
        Tenants::Defaults.seed!
        if @admin_email
          password = SecureRandom.alphanumeric(24)
          admin = User.create!(name: @admin_name.presence || @admin_email.split("@").first,
                               email_address: @admin_email, password: password, role: :client_admin)
        end
      end

      Result.new(tenant: tenant, admin: admin, admin_password: password)
    end
  end
end
