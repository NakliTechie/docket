module Imports
  # Salesforce export contract for the objects Docket actually owns: Account,
  # Contact, User, Case, Lead, and Opportunity. Roles, case statuses, and deal
  # stages are caller-supplied mappings; unknown values are reported and the
  # affected record is skipped.
  class Salesforce
    ACCOUNT_FIELDS = %w[Id Name Type CreatedDate LastModifiedDate IsDeleted].freeze
    CONTACT_FIELDS = %w[
      Id AccountId Name FirstName LastName Email Phone MobilePhone CreatedDate
      LastModifiedDate IsDeleted
    ].freeze
    USER_FIELDS = %w[
      Id Name Email IsActive Profile UserRole UserType CreatedDate LastModifiedDate
    ].freeze
    CASE_FIELDS = %w[
      Id AccountId ContactId OwnerId CaseNumber Subject Description Status Priority Origin
      CreatedDate LastModifiedDate ClosedDate IsClosed SuppliedEmail SuppliedName
      First_Response__c First_Response_Due__c Resolution_Due__c IsDeleted
    ].freeze
    LEAD_FIELDS = %w[
      Id OwnerId Name FirstName LastName Company Email Phone Status LeadSource Description
      CreatedDate LastModifiedDate IsConverted ConvertedDate CurrencyIsoCode AnnualRevenue
      IsDeleted
    ].freeze
    OPPORTUNITY_FIELDS = %w[
      Id AccountId OwnerId Name StageName Amount CurrencyIsoCode CloseDate IsClosed IsWon
      Probability Description CreatedDate LastModifiedDate IsDeleted
    ].freeze
    PRIORITY_MAP = {
      "low" => :low, "medium" => :normal, "normal" => :normal,
      "high" => :high, "critical" => :urgent
    }.freeze
    ORIGIN_MAP = {
      "email" => :email, "web" => :web_portal, "phone" => :phone,
      "portal" => :web_portal, "api" => :api
    }.freeze

    def self.call(...) = new(...).call
    def self.preview(...) = new(...).preview

    def initialize(payload: nil, file: nil, source: nil, role_map: {}, status_map: {},
                   stage_map: {}, lead_status_map: {}, lead_source_map: {},
                   dry_run: false, source_instance: "default", resume_token: nil,
                   batch_size: 200)
      @result = Result.new
      @input = Input.new(payload: payload, file: file, source: source, bare_entity: "Case")
      @role_map = role_map.stringify_keys
      @status_map = status_map.stringify_keys
      @stage_map = stage_map.stringify_keys
      @lead_status_map = lead_status_map.stringify_keys
      @lead_source_map = lead_source_map.stringify_keys
      @dry_run = dry_run
      @source_instance = source_instance
      @resume_token = resume_token
      @batch_size = batch_size
    rescue JsonRows::FormatError, ArgumentError => e
      @result.error!(e.message)
    end

    def preview(sample_size: 50)
      values = Hash.new { |hash, key| hash[key] = Set.new }
      dropped = Hash.new { |hash, key| hash[key] = Set.new }
      preview_entity("User", USER_FIELDS, sample_size) do |row|
        user_role_candidates(row).each { |role| values["roles"] << role }
      end
      preview_entity("Case", CASE_FIELDS, sample_size) { |row| values["case_statuses"] << row["Status"] if row["Status"].present? }
      preview_entity("Lead", LEAD_FIELDS, sample_size) do |row|
        values["lead_statuses"] << row["Status"] if row["Status"].present?
        values["lead_sources"] << row["LeadSource"] if row["LeadSource"].present?
      end
      preview_entity("Opportunity", OPPORTUNITY_FIELDS, sample_size) do |row|
        values["opportunity_stages"] << row["StageName"] if row["StageName"].present?
      end
      {
        source_values: values.transform_values { |set| set.to_a.sort },
        missing_mappings: {
          roles: unmapped(values["roles"], @role_map),
          case_statuses: unmapped(values["case_statuses"], @status_map),
          lead_statuses: unmapped(values["lead_statuses"], @lead_status_map),
          lead_sources: unmapped(values["lead_sources"], @lead_source_map),
          opportunity_stages: unmapped(values["opportunity_stages"], @stage_map)
        }.reject { |_, entries| entries.empty? },
        recommended_contract: {
          roles: User.roles.keys, case_statuses: Case.statuses.keys,
          lead_statuses: Lead.statuses.keys, lead_sources: Lead.sources.keys,
          opportunity_stage: "Pipeline name / pipeline stage name"
        },
        dropped_fields: @result.serialized_unmapped.select do |field, _values|
          field.start_with?("dropped.")
        end,
        errors: @result.errors
      }
    rescue JsonRows::FormatError => e
      { source_values: {}, missing_mappings: {}, recommended_contract: {}, errors: [ e.message ] }
    end

    def call
      return @result if @result.errors.any?

      @session = Session.new(source: "salesforce", source_instance: @source_instance,
                             dry_run: @dry_run, resume_token: @resume_token,
                             batch_size: @batch_size, result: @result)
      process("Account") { |row| import_account(row) }
      process("User") { |row| import_user(row) }
      process("Contact") { |row| import_contact(row) }
      if Features.enabled?("service_desk")
        process("Case") { |row| import_case(row) }
      else
        report_disabled("Case", "service_desk", "cases")
      end
      if Features.enabled?("crm")
        process("Lead") { |row| import_lead(row) }
        process("Opportunity") { |row| import_opportunity(row) }
      else
        report_disabled("Lead", "crm", "leads")
        report_disabled("Opportunity", "crm", "deals")
      end
      @session.finish!
      @session.result
    rescue JsonRows::FormatError, Session::ResumeError, ActiveRecord::RecordNotFound => e
      @result.error!(e.message)
      @result
    end

    private

    def process(entity, &block)
      @session.process(@input.rows(entity, optional: true), stream: entity, &block)
    end

    def report_disabled(entity, feature, kind)
      reported = false
      process(entity) do
        unless reported
          @session.result.error!("#{entity} rows were not imported because the #{feature} module is disabled")
          reported = true
        end
        @session.result.skip!(kind)
      end
    end

    def import_account(row)
      return invalid_row("Account", row) unless row.is_a?(Hash)
      inspect_fields(row, "Account", ACCOUNT_FIELDS)
      id = source_id(row, "Account") or return
      if deleted_source_row?(row)
        return tombstone("Account", id, "organisations", row["LastModifiedDate"])
      end
      return @session.result.skip!("organisations") if row["Name"].blank?

      existing = @session.identity_target("Account", id) || Organisation.find_by(name: row["Name"])
      attrs = { "name" => row["Name"], "kind" => "company" }
      add_times(attrs, row)
      @session.sync(source_type: "Account", external_id: id, kind: "organisations",
                    attributes: attrs, source_updated_at: row["LastModifiedDate"],
                    existing: existing) { Organisation.new }
    end

    def import_user(row)
      return invalid_row("User", row) unless row.is_a?(Hash)
      inspect_fields(row, "User", USER_FIELDS)
      id = source_id(row, "User") or return
      role = mapped_user_role(row)
      return @session.result.skip!("users") unless role
      email = row["Email"].presence
      unless email
        @session.result.unmapped!("user_email", id)
        return @session.result.skip!("users")
      end

      existing = @session.identity_target("User", id) || User.find_by(email_address: email)
      attrs = { "name" => row["Name"].presence || email.split("@").first,
                "email_address" => email }
      attrs["active"] = row["IsActive"] unless row["IsActive"].nil?
      attrs["role"] = role if existing.nil?
      add_times(attrs, row)
      @session.sync(source_type: "User", external_id: id, kind: "users",
                    attributes: attrs, source_updated_at: row["LastModifiedDate"],
                    existing: existing, metadata: { mapped_role: role }) do
        User.new(password: SecureRandom.base64(48))
      end
    end

    def import_contact(row)
      return invalid_row("Contact", row) unless row.is_a?(Hash)
      inspect_fields(row, "Contact", CONTACT_FIELDS)
      id = source_id(row, "Contact") or return
      if deleted_source_row?(row)
        return tombstone("Contact", id, "contacts", row["LastModifiedDate"])
      end
      email = row["Email"].presence
      existing = @session.identity_target("Contact", id)
      existing ||= Contact.find_by(email: email) if email
      if existing&.external_id.present? && @session.identity_target("Contact", id).nil?
        @session.result.unmapped!("protected_contact", id)
        return @session.result.skip!("contacts")
      end
      organisation = @session.identity_target("Account", row["AccountId"].to_s)
      attrs = {
        "name" => row["Name"].presence || [ row["FirstName"], row["LastName"] ].compact.join(" ").presence || email,
        "email" => email,
        "phone" => row["Phone"].presence || row["MobilePhone"].presence,
        "external_id" => id
      }.compact
      attrs["organisation_id"] = organisation.id if organisation
      @session.result.unmapped!("AccountId", row["AccountId"]) if row["AccountId"].present? && organisation.nil?
      add_times(attrs, row)
      @session.sync(source_type: "Contact", external_id: id, kind: "contacts",
                    attributes: attrs, source_updated_at: row["LastModifiedDate"],
                    existing: existing) { Contact.new }
    end

    def import_case(row)
      return invalid_row("Case", row) unless row.is_a?(Hash)
      inspect_fields(row, "Case", CASE_FIELDS)
      id = source_id(row, "Case") or return
      if deleted_source_row?(row)
        return tombstone("Case", id, "cases", row["LastModifiedDate"])
      end
      status = @status_map[row["Status"].to_s]
      unless Case.statuses.key?(status.to_s)
        @session.result.unmapped!("case_status", row["Status"])
        return @session.result.skip!("cases")
      end
      contact = @session.identity_target("Contact", row["ContactId"].to_s)
      unless contact
        @session.result.unmapped!("ContactId", row["ContactId"].presence || "missing")
        return @session.result.skip!("cases")
      end

      existing = @session.identity_target("Case", id) ||
                 Case.with_deleted.find_by(external_id: "salesforce:#{id}")
      attrs = {
        "external_id" => "salesforce:#{id}", "contact_id" => contact.id,
        "subject" => row["Subject"].presence || "Case #{row['CaseNumber'].presence || id}",
        "description" => row["Description"], "status" => status
      }
      priority = PRIORITY_MAP[row["Priority"].to_s.downcase]
      attrs["priority"] = priority if priority
      @session.result.unmapped!("case_priority", row["Priority"]) if row["Priority"].present? && priority.nil?
      channel = ORIGIN_MAP[row["Origin"].to_s.downcase]
      attrs["channel"] = channel if channel
      @session.result.unmapped!("case_origin", row["Origin"]) if row["Origin"].present? && channel.nil?
      owner = @session.identity_target("User", row["OwnerId"].to_s)
      attrs["assignee_id"] = owner.id if owner
      add_times(attrs, row)
      attrs["closed_at"] = parse_time(row["ClosedDate"]) if row.key?("ClosedDate")
      attrs["first_responded_at"] = parse_time(row["First_Response__c"]) if row.key?("First_Response__c")
      attrs["first_response_due_at"] = parse_time(row["First_Response_Due__c"]) if row.key?("First_Response_Due__c")
      attrs["resolution_due_at"] = parse_time(row["Resolution_Due__c"]) if row.key?("Resolution_Due__c")
      @session.sync(source_type: "Case", external_id: id, kind: "cases",
                    attributes: attrs, source_updated_at: row["LastModifiedDate"],
                    existing: existing) { Case.new }
    end

    def import_lead(row)
      return invalid_row("Lead", row) unless row.is_a?(Hash)
      inspect_fields(row, "Lead", LEAD_FIELDS)
      id = source_id(row, "Lead") or return
      if deleted_source_row?(row)
        return tombstone("Lead", id, "leads", row["LastModifiedDate"])
      end
      status = @lead_status_map[row["Status"].to_s]
      source = @lead_source_map[row["LeadSource"].to_s]
      unless Lead.statuses.key?(status.to_s) && Lead.sources.key?(source.to_s)
        @session.result.unmapped!("lead_status", row["Status"]) unless Lead.statuses.key?(status.to_s)
        @session.result.unmapped!("lead_source", row["LeadSource"]) unless Lead.sources.key?(source.to_s)
        return @session.result.skip!("leads")
      end
      existing = @session.identity_target("Lead", id) || Lead.find_by(external_id: id)
      owner = @session.identity_target("User", row["OwnerId"].to_s)
      attrs = {
        "external_id" => id, "name" => row["Name"].presence ||
          [ row["FirstName"], row["LastName"] ].compact.join(" "),
        "company_name" => row["Company"], "email" => row["Email"],
        "phone" => row["Phone"], "notes" => row["Description"],
        "status" => status, "source" => source, "owner_id" => owner&.id
      }.compact
      add_times(attrs, row)
      @session.sync(source_type: "Lead", external_id: id, kind: "leads",
                    attributes: attrs, source_updated_at: row["LastModifiedDate"],
                    existing: existing) { Lead.new }
    end

    def import_opportunity(row)
      return invalid_row("Opportunity", row) unless row.is_a?(Hash)
      inspect_fields(row, "Opportunity", OPPORTUNITY_FIELDS)
      id = source_id(row, "Opportunity") or return
      if deleted_source_row?(row)
        return tombstone("Opportunity", id, "deals", row["LastModifiedDate"])
      end
      pipeline, stage = mapped_stage(row["StageName"])
      unless pipeline && stage
        @session.result.unmapped!("opportunity_stage", row["StageName"])
        return @session.result.skip!("deals")
      end
      existing = @session.identity_target("Opportunity", id) || Deal.find_by(external_id: id)
      owner = @session.identity_target("User", row["OwnerId"].to_s)
      organisation = @session.identity_target("Account", row["AccountId"].to_s)
      attrs = {
        "external_id" => id, "name" => row["Name"], "pipeline_id" => pipeline.id,
        "pipeline_stage_id" => stage.id, "owner_id" => owner&.id,
        "organisation_id" => organisation&.id,
        "value_cents" => row["Amount"].present? ? Cents.from(row["Amount"]) : nil,
        "currency" => row["CurrencyIsoCode"].presence || "INR",
        "expected_close_on" => parse_date(row["CloseDate"])
      }.compact
      attrs["closed_at"] = parse_time(row["LastModifiedDate"]) if row["IsClosed"] == true
      add_times(attrs, row)
      @session.sync(source_type: "Opportunity", external_id: id, kind: "deals",
                    attributes: attrs, source_updated_at: row["LastModifiedDate"],
                    existing: existing) { Deal.new }
    end

    def mapped_user_role(row)
      candidates = user_role_candidates(row)
      key = candidates.find { |candidate| @role_map.key?(candidate) }
      role = @role_map[key].to_s if key
      return role if User.roles.key?(role)

      candidates.each { |candidate| @session.result.unmapped!("user_role", candidate) }
      nil
    end

    def user_role_candidates(row)
      [ row.dig("Profile", "Name"), row.dig("UserRole", "Name"), row["UserType"] ]
        .compact.map(&:to_s)
    end

    def mapped_stage(source)
      target = @stage_map[source.to_s]
      pipeline_name, stage_name = target.is_a?(Array) ? target : target.to_s.split("/", 2)
      pipeline = Pipeline.find_by("LOWER(name) = ?", pipeline_name.to_s.downcase)
      stage = pipeline&.pipeline_stages&.find_by("LOWER(name) = ?", stage_name.to_s.downcase)
      [ pipeline, stage ]
    end

    def preview_entity(entity, fields, limit)
      @input.rows(entity, optional: true).first(limit).each do |row|
        next unless row.is_a?(Hash)
        FieldContract.new(@result, entity, fields).inspect!(row)
        yield row
      end
    end

    def unmapped(values, mapping)
      values.reject { |value| mapping.key?(value.to_s) }.to_a.sort
    end

    def source_id(row, entity)
      id = row["Id"].to_s
      return id if id.present?

      @session.result.error!("#{entity}: Id is required")
      nil
    end

    def tombstone(source_type, external_id, kind, updated_at)
      @session.tombstone(source_type: source_type, external_id: external_id, kind: kind,
                         source_updated_at: updated_at)
    end

    def deleted_source_row?(row)
      ActiveModel::Type::Boolean.new.cast(row["IsDeleted"])
    end

    def inspect_fields(row, entity, fields)
      FieldContract.new(@session.result, entity, fields).inspect!(row)
    end

    def add_times(attrs, row)
      attrs["created_at"] = parse_time(row["CreatedDate"]) if row.key?("CreatedDate")
      attrs["updated_at"] = parse_time(row["LastModifiedDate"]) if row.key?("LastModifiedDate")
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      @session&.result&.unmapped!("invalid_timestamp", value)
      nil
    end

    def parse_date(value)
      value.present? ? Date.parse(value.to_s) : nil
    rescue ArgumentError
      @session&.result&.unmapped!("invalid_date", value)
      nil
    end

    def invalid_row(entity, row)
      @session.result.error!("#{entity}: expected an object, got #{row.class}")
    end
  end
end
