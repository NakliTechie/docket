# Migration entry points. Every import defaults to a dry run and every mapping
# is a checked-in/reviewable JSON contract rather than an implicit guess.
namespace :docket do
  namespace :import do
    def report(result, label)
      puts "\n#{label}: #{result.summary}"
      result.serialized_unmapped.each do |field, values|
        puts "  UNMAPPED #{field}: #{values.join(', ')}"
      end
      result.conflicts.first(20).each do |conflict|
        puts "  CONFLICT #{conflict['source_type']} #{conflict['external_id']} #{conflict['field']}"
      end
      result.errors.first(20).each { |error| puts "  ERROR #{error}" }
      puts "  ...and #{result.errors.size - 20} more errors" if result.errors.size > 20
      if result.run_id
        run = ImportRun.find(result.run_id)
        puts "  Run: #{run.id}  Resume token: #{run.resume_token}"
        puts "  Checkpoint: #{JSON.generate(run.checkpoint)}"
      end
      if dry_run?
        puts "  Dry-run attachment checks validate export metadata; bytes are downloaded only on APPLY."
      end
      puts result.errors.any? ? "\nFinished WITH ERRORS." : "\nFinished cleanly."
    end

    def tenant_scope(&block)
      slug = ENV["TENANT"].presence
      tenant = slug ? Tenant.find_by!(slug: slug) : Tenant.primary
      abort "No tenant found. Pass TENANT=<slug>." if tenant.nil?
      puts "Tenant: #{tenant.name} (#{tenant.slug})"
      ActsAsTenant.with_tenant(tenant, &block)
    end

    def required_env(key)
      ENV[key].presence || abort("Pass #{key}=...")
    end

    def file_path(key = "FILE")
      path = required_env(key)
      abort "#{key} does not exist: #{path}" unless File.file?(path)
      path
    end

    def json_contract(key, default = {})
      path = ENV[key].presence
      return default if path.nil?
      JSON.parse(File.read(path))
    rescue JSON::ParserError => e
      abort "#{key} is not valid JSON: #{e.message}"
    end

    def dry_run? = ENV["APPLY"] != "1"
    def batch_size = Integer(ENV.fetch("BATCH_SIZE", "200"), 10)
    def source_instance = required_env("SOURCE_INSTANCE")
    def allow_insecure_http? = ENV["ALLOW_INSECURE_MIGRATION_HTTP"] == "1"

    def common_options
      {
        dry_run: dry_run?, source_instance: source_instance,
        resume_token: ENV["RESUME_TOKEN"].presence, batch_size: batch_size
      }
    end

    def announce
      if dry_run?
        puts "DRY RUN — domain rows will be rolled back. Re-run with APPLY=1 to commit.\n"
      else
        puts "APPLYING in batches of #{batch_size}.\n"
      end
    end

    desc "Import a Jira JSON export. FILE=export.json SOURCE_INSTANCE=stable-id [PROJECT=KEY] [MAPS=mappings.json] [APPLY=1]"
    task jira: :environment do
      announce
      tenant_scope do
        maps = json_contract("MAPS")
        project = ENV["PROJECT"].present? ? Project.find_by!(key: ENV["PROJECT"].upcase) : nil
        result = Imports::Jira.call(
          file: file_path, project: project, status_map: maps.fetch("statuses", {}),
          role_map: maps.fetch("roles", {}), custom_field_map: maps.fetch("custom_fields", {}),
          actor: User.staff.first, **common_options
        )
        report(result, "Jira import")
      end
    end

    desc "Import directly from Jira Cloud. SOURCE_INSTANCE=stable-id JIRA_URL=... JIRA_EMAIL=... JIRA_API_TOKEN=... [MAPS=...] [APPLY=1]"
    task jira_api: :environment do
      announce
      tenant_scope do
        maps = json_contract("MAPS")
        source = Imports::JiraApi.new(
          base_url: required_env("JIRA_URL"), email: required_env("JIRA_EMAIL"),
          api_token: required_env("JIRA_API_TOKEN"), jql: ENV["JIRA_JQL"].presence,
          allow_insecure: allow_insecure_http?
        )
        result = Imports::Jira.call(source: source, status_map: maps.fetch("statuses", {}),
                                    role_map: maps.fetch("roles", {}),
                                    custom_field_map: maps.fetch("custom_fields", {}),
                                    actor: User.staff.first, **common_options)
        report(result, "Jira API import")
      end
    end

    desc "Import a Freshdesk JSON export. FILE=export.json SOURCE_INSTANCE=stable-id [MAPS=mappings.json] [APPLY=1]"
    task freshdesk: :environment do
      announce
      tenant_scope do
        maps = json_contract("MAPS")
        result = Imports::Freshdesk.call(
          file: file_path, default_queue: CaseQueue.first,
          status_map: maps.fetch("statuses", {}), role_map: maps.fetch("roles", {}),
          custom_field_map: maps.fetch("custom_fields", {}),
          **common_options
        )
        report(result, "Freshdesk import")
      end
    end

    desc "Import directly from Freshdesk. SOURCE_INSTANCE=stable-id FRESHDESK_DOMAIN=... FRESHDESK_API_KEY=... [MAPS=...] [APPLY=1]"
    task freshdesk_api: :environment do
      announce
      tenant_scope do
        maps = json_contract("MAPS")
        domain = required_env("FRESHDESK_DOMAIN")
        source = Imports::FreshdeskApi.new(domain: domain,
                                            api_key: required_env("FRESHDESK_API_KEY"),
                                            allow_insecure: allow_insecure_http?)
        result = Imports::Freshdesk.call(
          source: source, default_queue: CaseQueue.first,
          status_map: maps.fetch("statuses", {}), role_map: maps.fetch("roles", {}),
          custom_field_map: maps.fetch("custom_fields", {}),
          **common_options
        )
        report(result, "Freshdesk API import")
      end
    end

    desc "Preview a Salesforce export mapping. FILE=export.json [MAPS=mappings.json]"
    task salesforce_preview: :environment do
      tenant_scope do
        maps = json_contract("MAPS")
        preview = Imports::Salesforce.preview(
          file: file_path, role_map: maps.fetch("roles", {}),
          status_map: maps.fetch("case_statuses", {}),
          stage_map: maps.fetch("opportunity_stages", {}),
          lead_status_map: maps.fetch("lead_statuses", {}),
          lead_source_map: maps.fetch("lead_sources", {}),
          custom_field_maps: maps.fetch("custom_fields", {})
        )
        puts JSON.pretty_generate(preview)
      end
    end

    desc "Import a Salesforce export. FILE=export.json MAPS=mappings.json SOURCE_INSTANCE=stable-id [APPLY=1]"
    task salesforce: :environment do
      announce
      tenant_scope do
        maps = json_contract("MAPS")
        result = Imports::Salesforce.call(
          file: file_path, role_map: maps.fetch("roles", {}),
          status_map: maps.fetch("case_statuses", {}),
          stage_map: maps.fetch("opportunity_stages", {}),
          lead_status_map: maps.fetch("lead_statuses", {}),
          lead_source_map: maps.fetch("lead_sources", {}),
          custom_field_maps: maps.fetch("custom_fields", {}), **common_options
        )
        report(result, "Salesforce import")
      end
    end

    desc "Preview a generic CSV contract. FILE=data.csv CONTRACT=mapping.json"
    task csv_preview: :environment do
      tenant_scope do
        contract = json_contract("CONTRACT")
        preview = Imports::Csv.preview(
          file: file_path, entity: contract.fetch("entity"),
          identity_column: contract.fetch("identity_column"),
          mapping: contract.fetch("mapping"), value_maps: contract.fetch("value_maps", {}),
          defaults: contract.fetch("defaults", {})
        )
        puts JSON.pretty_generate(preview)
      end
    end

    desc "Import a generic CSV contract. FILE=data.csv CONTRACT=mapping.json SOURCE_INSTANCE=stable-id [APPLY=1]"
    task csv: :environment do
      announce
      tenant_scope do
        contract = json_contract("CONTRACT")
        result = Imports::Csv.call(
          file: file_path, entity: contract.fetch("entity"),
          identity_column: contract.fetch("identity_column"),
          mapping: contract.fetch("mapping"), value_maps: contract.fetch("value_maps", {}),
          defaults: contract.fetch("defaults", {}), **common_options
        )
        report(result, "CSV import")
      end
    end

    desc "Reconcile a full source inventory. SOURCE=freshdesk INVENTORY=inventory.json [SOURCE_INSTANCE=...]"
    task reconcile: :environment do
      tenant_scope do
        inventory = json_contract("INVENTORY")
        result = Imports::Reconciliation.call(
          source: required_env("SOURCE"), source_instance: source_instance,
          inventory: inventory, full: ENV["DELTA"] != "1"
        )
        puts JSON.pretty_generate(result)
        abort "Reconciliation found discrepancies." unless result[:ok]
      end
    end

    desc "Import a KanZen board. FILE=board.kanzen.json [KEY=ABC] [APPLY=1]"
    task kanzen: :environment do
      announce
      tenant_scope do
        result = Imports::Kanzen.call(payload: File.read(file_path), key: ENV["KEY"].presence,
                                      dry_run: dry_run?, actor: User.staff.first)
        report(result, "KanZen import")
      end
    end

    desc "Import a CPGRAMS grievance export. FILE=grievances.json SOURCE_INSTANCE=stable-id [MAPS=maps.json] [APPLY=1]"
    task cpgrams: :environment do
      announce
      tenant_scope do
        maps = json_contract("MAPS")
        result = Imports::Cpgrams.call(
          file: file_path, default_queue: CaseQueue.first,
          status_map: maps.fetch("statuses", {}), queue_map: maps.fetch("ministries", {}),
          **common_options
        )
        report(result, "CPGRAMS import")
      end
    end
  end
end
