# Migration entry points for a new customer. Every task defaults to a DRY RUN:
# it reports exactly what would happen — including every source value it has no
# mapping for — and writes nothing until you pass APPLY=1.
namespace :docket do
  namespace :import do
    def report(result, label)
      puts "\n#{label}: #{result.summary}"
      result.to_h[:unmapped].each do |field, values|
        puts "  UNMAPPED #{field}: #{values.join(', ')}"
        puts "    (these fell back to a default — supply a mapping if that is wrong)"
      end
      result.errors.first(20).each { |e| puts "  ERROR #{e}" }
      puts "  ...and #{result.errors.size - 20} more errors" if result.errors.size > 20
      puts result.errors.any? ? "\nFinished WITH ERRORS." : "\nFinished cleanly."
    end

    def tenant_scope(&block)
      slug = ENV["TENANT"].presence
      tenant = slug ? Tenant.find_by!(slug: slug) : Tenant.primary
      abort "No tenant found. Pass TENANT=<slug>." if tenant.nil?
      puts "Tenant: #{tenant.name} (#{tenant.slug})"
      ActsAsTenant.with_tenant(tenant, &block)
    end

    def payload_from(env_key = "FILE")
      path = ENV[env_key].presence or abort "Pass #{env_key}=/path/to/export.json"
      File.read(path)
    end

    def dry_run? = ENV["APPLY"] != "1"

    def announce
      puts dry_run? ? "DRY RUN — nothing will be written. Re-run with APPLY=1 to commit.\n" : "APPLYING.\n"
    end

    desc "Import a Jira export into work items. FILE=export.json [PROJECT=KEY] [APPLY=1]"
    task jira: :environment do
      announce
      tenant_scope do
        project = ENV["PROJECT"].present? ? Project.find_by!(key: ENV["PROJECT"].upcase) : nil
        result = Imports::Jira.call(payload: payload_from, project: project,
                                    dry_run: dry_run?, actor: User.staff.first)
        report(result, "Jira import")
      end
    end

    desc "Import a Freshdesk export into cases. FILE=export.json [APPLY=1]"
    task freshdesk: :environment do
      announce
      tenant_scope do
        result = Imports::Freshdesk.call(payload: payload_from, dry_run: dry_run?,
                                         default_queue: CaseQueue.first)
        report(result, "Freshdesk import")
      end
    end

    desc "Import a KanZen board (.kanzen.json) into a project. FILE=board.kanzen.json [KEY=ABC] [APPLY=1]"
    task kanzen: :environment do
      announce
      tenant_scope do
        result = Imports::Kanzen.call(payload: payload_from, key: ENV["KEY"].presence,
                                      dry_run: dry_run?, actor: User.staff.first)
        report(result, "KanZen import")
      end
    end
  end
end
