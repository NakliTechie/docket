# Migration-out entry points. The CPGRAMS export is the status/ATR round-trip a
# department uploads back to CPGRAMS after working grievances in Docket.
namespace :docket do
  namespace :export do
    def export_tenant_scope(&block)
      slug = ENV["TENANT"].presence
      tenant = slug ? Tenant.find_by!(slug: slug) : Tenant.primary
      abort "No tenant found. Pass TENANT=<slug>." if tenant.nil?
      warn "Tenant: #{tenant.name} (#{tenant.slug})"
      ActsAsTenant.with_tenant(tenant, &block)
    end

    desc "Export CPGRAMS grievance cases (status + ATR) as JSON. [OUT=grievances.json] (else stdout)"
    task cpgrams: :environment do
      export_tenant_scope do
        payload = Exports::Cpgrams.new.to_json
        if (out = ENV["OUT"].presence)
          File.write(out, payload)
          warn "Wrote #{JSON.parse(payload)['grievances'].size} grievances to #{out}"
        else
          puts payload
        end
      end
    end
  end
end
