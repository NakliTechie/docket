module Imports
  # Generic, contract-driven CSV importer. The same mapping powers preview and
  # apply; preview therefore exposes missing columns, dropped columns, and enum
  # values before any durable run can begin.
  class Csv
    CUSTOM_FIELD_ENTITIES = CustomFieldDefinition::RESOURCE_TYPES.freeze

    ENTITY_CONTRACTS = {
      "organisations" => {
        model: Organisation, allowed: %w[name kind created_at updated_at], required: %w[name]
      },
      "contacts" => {
        model: Contact,
        allowed: %w[name email phone external_id preferred_language organisation_external_id
                    email_consent sms_consent created_at updated_at],
        required: %w[name]
      },
      "users" => {
        model: User, allowed: %w[name email_address role active created_at updated_at],
        required: %w[name email_address role]
      },
      "cases" => {
        model: Case,
        allowed: %w[subject description external_id status priority channel contact_external_id
                    assignee_email created_at updated_at resolved_at closed_at first_responded_at
                    first_response_due_at resolution_due_at],
        required: %w[subject contact_external_id status]
      },
      "work_items" => {
        model: WorkItem,
        allowed: %w[title description source_key kind priority estimate due_on labels project_key
                    workflow_state assignee_email reporter_email created_at updated_at closed_at],
        required: %w[title project_key workflow_state]
      },
      "leads" => {
        model: Lead,
        allowed: %w[name email phone company_name external_id source status notes labels owner_email
                    value_estimate email_consent sms_consent created_at updated_at],
        required: %w[name]
      },
      "deals" => {
        model: Deal,
        allowed: %w[name external_id pipeline pipeline_stage owner_email contact_external_id
                    organisation_external_id value currency expected_close_on lost_reason labels
                    created_at updated_at closed_at],
        required: %w[name pipeline pipeline_stage]
      }
    }.freeze
    ENUMS = {
      "users" => { "role" => User.roles },
      "cases" => { "status" => Case.statuses, "priority" => Case.priorities,
                     "channel" => Case.channels },
      "work_items" => { "kind" => WorkItem.kinds, "priority" => WorkItem.priorities },
      "leads" => { "source" => Lead.sources, "status" => Lead.statuses },
      "deals" => { "lost_reason" => Deal.lost_reasons }
    }.freeze

    def self.preview(...) = new(...).preview
    def self.call(...) = new(...).call

    def initialize(file: nil, payload: nil, entity:, identity_column:, mapping:,
                   value_maps: {}, defaults: {}, dry_run: false,
                   source_instance: "default", resume_token: nil, batch_size: 200)
      @file = file
      @payload = payload
      @entity = entity.to_s
      @identity_column = identity_column.to_s
      @mapping = mapping.stringify_keys
      @value_maps = value_maps.to_h.transform_keys(&:to_s).transform_values(&:stringify_keys)
      @defaults = defaults.stringify_keys
      @dry_run = dry_run
      @source_instance = source_instance
      @resume_token = resume_token
      @batch_size = batch_size
      @result = Result.new
    end

    def preview(sample_size: 25)
      errors = contract_errors
      headers, sample = read_preview(sample_size)
      mapped_columns = @mapping.values.map(&:to_s).to_set << @identity_column
      missing_columns = mapped_columns.reject { |column| headers.include?(column) }.to_a.sort
      errors.concat(missing_columns.map { |column| "CSV column #{column.inspect} is missing" })
      missing_targets = contract.fetch(:required).reject { |field| @mapping.key?(field) || @defaults.key?(field) }
      errors.concat(missing_targets.map { |field| "required target #{field.inspect} is not mapped" })
      {
        entity: @entity, headers: headers, sample: sample,
        mapping: @mapping, suggested_mapping: suggested_mapping(headers),
        unmapped_columns: headers.reject { |column| mapped_columns.include?(column) },
        missing_columns: missing_columns, missing_required_targets: missing_targets,
        unmapped_values: preview_unmapped_values(sample), errors: errors.uniq
      }
    rescue ::CSV::MalformedCSVError, Errno::ENOENT => e
      { entity: @entity, headers: [], sample: [], mapping: @mapping,
        suggested_mapping: {}, unmapped_columns: [], missing_columns: [],
        missing_required_targets: [], unmapped_values: {}, errors: [ e.message ] }
    end

    def call
      check = preview
      check[:errors].each { |error| @result.error!(error) }
      return @result if @result.errors.any?
      return feature_error unless feature_enabled?

      session = Session.new(source: "csv", source_instance: @source_instance,
                            dry_run: @dry_run, resume_token: @resume_token,
                            batch_size: @batch_size,
                            options: { entity: @entity, mapping: @mapping })
      @session = session
      session.process(rows, stream: @entity) { |row| import_row(row.to_h) }
      session.finish!
      session.result
    rescue ::CSV::MalformedCSVError, Session::ResumeError, Errno::ENOENT => e
      @result.error!(e.message)
      @result
    end

    private

    def contract
      ENTITY_CONTRACTS.fetch(@entity)
    end

    def contract_errors
      return [ "unsupported CSV entity #{@entity.inspect}" ] unless ENTITY_CONTRACTS.key?(@entity)

      targets = @mapping.keys | @defaults.keys
      unknown = targets.reject { |field| contract.fetch(:allowed).include?(field) || valid_custom_field_target?(field) }
      errors = unknown.map { |field| "target field #{field.inspect} is not allowed for #{@entity}" }
      custom_field_targets(targets).each do |target|
        key = target.delete_prefix("custom_fields.")
        unless custom_field_definitions.key?(key)
          errors << "custom field #{key.inspect} is not defined for #{@entity}"
        end
      end
      errors << "identity_column is required" if @identity_column.blank?
      errors
    end

    def rows
      if @file
        ::CSV.foreach(@file, headers: true, encoding: "bom|utf-8")
      else
        ::CSV.new(StringIO.new(@payload.to_s), headers: true).each
      end
    end

    def read_preview(limit)
      headers = []
      sample = []
      rows.each_with_index do |row, index|
        headers = row.headers.compact.map(&:to_s)
        sample << row.to_h
        break if index + 1 >= limit
      end
      [ headers, sample ]
    end

    def import_row(row)
      FieldContract.new(@session.result, "csv.#{@entity}",
                        @mapping.values + [ @identity_column ]).inspect!(row)
      external_id = row[@identity_column].to_s
      if external_id.blank?
        @session.result.error!("#{@entity}: #{@identity_column} is blank")
        @session.result.skip!(@entity)
        return
      end

      attrs = nested_attributes(@defaults).merge(mapped_attributes(row)) do |key, old_value, new_value|
        key == "custom_fields" ? old_value.merge(new_value) : new_value
      end
      return @session.result.skip!(@entity) if attrs.nil?

      existing = @session.identity_target(@entity.singularize, external_id)
      existing ||= existing_target(external_id, attrs)
      builder, final_attrs = build_target(attrs, external_id)
      return @session.result.skip!(@entity) if builder.nil?

      @session.sync(source_type: @entity.singularize, external_id: external_id,
                    kind: @entity, attributes: final_attrs,
                    source_updated_at: final_attrs["updated_at"], existing: existing,
                    metadata: { "identity_column" => @identity_column }) { builder.call }
    end

    def mapped_attributes(row)
      @mapping.each_with_object({}) do |(target, source), attributes|
        next unless row.key?(source)

        value = row[source]
        converted = convert_value(target, value)
        return if converted == :unmapped
        if target.start_with?("custom_fields.")
          attributes["custom_fields"] ||= {}
          attributes["custom_fields"][target.delete_prefix("custom_fields.")] = converted
        else
          attributes[target] = converted
        end
      end
    end

    def convert_value(target, value)
      return nil if value.nil? || value == ""

      mapped = @value_maps.fetch(target, {}).fetch(value.to_s, value)
      if target.start_with?("custom_fields.")
        definition = custom_field_definitions[target.delete_prefix("custom_fields.")]
        mapped = mapped.to_s.split(/[;,]/).map(&:strip).reject(&:blank?) if definition&.field_type_multi_select?
        result = CustomFields::Type.coerce(definition, mapped)
        unless result.valid?
          @session&.result&.unmapped!(target, value)
          return :unmapped
        end
        return result.value
      end
      enum = ENUMS.dig(@entity, target)
      if enum && !enum.key?(mapped.to_s)
        @session&.result&.unmapped!(target, value)
        return :unmapped
      end
      case target
      when /(?:_at)\z/ then Time.zone.parse(mapped.to_s)
      when /(?:_on)\z/ then Date.parse(mapped.to_s)
      when "active", "email_consent", "sms_consent" then ActiveModel::Type::Boolean.new.cast(mapped)
      when "estimate", "value", "value_estimate" then BigDecimal(mapped.to_s)
      when "labels" then mapped.to_s.split(/[;,]/).map(&:strip).reject(&:blank?)
      else mapped
      end
    rescue ArgumentError
      @session&.result&.unmapped!(target, value)
      :unmapped
    end

    def existing_target(external_id, attrs)
      model = contract.fetch(:model)
      return model.find_by(external_id: attrs["external_id"].presence || external_id) if model.column_names.include?("external_id")
      return User.find_by(email_address: attrs["email_address"]) if model == User && attrs["email_address"].present?
      return Organisation.find_by(name: attrs["name"]) if model == Organisation && attrs["name"].present?

      nil
    end

    def build_target(attrs, external_id)
      attrs = attrs.dup
      case @entity
      when "organisations"
        [ -> { Organisation.new }, attrs ]
      when "contacts"
        attrs["external_id"] ||= external_id
        resolve_organisation!(attrs)
        [ -> { Contact.new }, attrs ]
      when "users"
        [ -> { User.new(password: SecureRandom.base64(48)) }, attrs ]
      when "cases"
        return unless resolve_case_associations!(attrs)
        attrs["external_id"] ||= "csv:#{external_id}"
        [ -> { Case.new }, attrs ]
      when "work_items"
        project = resolve_work_associations!(attrs)
        return unless project
        attrs["source_key"] ||= external_id
        [ -> { WorkItem.new(project: project, source_key: attrs["source_key"]) }, attrs ]
      when "leads"
        attrs["external_id"] ||= external_id
        attrs["value_estimate_cents"] = Cents.from(attrs.delete("value_estimate")) if attrs.key?("value_estimate")
        resolve_user!(attrs, "owner_email", "owner_id")
        [ -> { Lead.new }, attrs ]
      when "deals"
        return unless resolve_deal_associations!(attrs)
        attrs["external_id"] ||= external_id
        attrs["value_cents"] = Cents.from(attrs.delete("value")) if attrs.key?("value")
        [ -> { Deal.new }, attrs ]
      end
    end

    def resolve_organisation!(attrs)
      external_id = attrs.delete("organisation_external_id")
      return if external_id.blank?

      organisation = Organisation.find_by(external_id: external_id) if Organisation.column_names.include?("external_id")
      organisation ||= @session.identity_target("organisation", external_id)
      if organisation
        attrs["organisation_id"] = organisation.id
      else
        @session.result.unmapped!("organisation_external_id", external_id)
      end
    end

    def resolve_case_associations!(attrs)
      external_id = attrs.delete("contact_external_id")
      contact = Contact.find_by(external_id: external_id) ||
                @session.identity_target("contact", external_id.to_s)
      unless contact
        @session.result.unmapped!("contact_external_id", external_id)
        return false
      end
      attrs["contact_id"] = contact.id
      resolve_user!(attrs, "assignee_email", "assignee_id")
      true
    end

    def resolve_work_associations!(attrs)
      key = attrs.delete("project_key")
      state_name = attrs.delete("workflow_state")
      project = Project.find_by(key: key.to_s.upcase)
      unless project
        @session.result.unmapped!("project_key", key)
        return
      end
      state = project.workflow_states.find_by("LOWER(name) = ?", state_name.to_s.downcase)
      unless state
        @session.result.unmapped!("workflow_state", state_name)
        return
      end
      attrs["project_id"] = project.id
      attrs["workflow_state_id"] = state.id
      resolve_user!(attrs, "assignee_email", "assignee_id")
      resolve_user!(attrs, "reporter_email", "reporter_id")
      project
    end

    def resolve_deal_associations!(attrs)
      pipeline_name = attrs.delete("pipeline")
      stage_name = attrs.delete("pipeline_stage")
      pipeline = Pipeline.find_by("LOWER(name) = ?", pipeline_name.to_s.downcase)
      stage = pipeline&.pipeline_stages&.find_by("LOWER(name) = ?", stage_name.to_s.downcase)
      unless pipeline && stage
        @session.result.unmapped!("pipeline_stage", "#{pipeline_name}/#{stage_name}")
        return false
      end
      attrs["pipeline_id"] = pipeline.id
      attrs["pipeline_stage_id"] = stage.id
      resolve_user!(attrs, "owner_email", "owner_id")
      resolve_external_association!(attrs, "contact_external_id", "contact_id", Contact)
      resolve_external_association!(attrs, "organisation_external_id", "organisation_id", Organisation)
      true
    end

    def resolve_user!(attrs, source, target)
      email = attrs.delete(source)
      return if email.blank?
      user = User.find_by(email_address: email)
      user ? attrs[target] = user.id : @session.result.unmapped!(source, email)
    end

    def resolve_external_association!(attrs, source, target, model)
      external_id = attrs.delete(source)
      return if external_id.blank?
      record = model.find_by(external_id: external_id) if model.column_names.include?("external_id")
      record ? attrs[target] = record.id : @session.result.unmapped!(source, external_id)
    end

    def suggested_mapping(headers)
      contract.fetch(:allowed).each_with_object({}) do |field, suggestions|
        normalized = field.delete_suffix("_address").delete_suffix("_external_id").tr("_", "")
        found = headers.find { |header| header.to_s.downcase.gsub(/[^a-z0-9]/, "") == normalized }
        suggestions[field] = found if found
      end
    end

    def valid_custom_field_target?(field)
      CUSTOM_FIELD_ENTITIES.include?(@entity) && field.start_with?("custom_fields.")
    end

    def custom_field_targets(targets)
      targets.select { |field| field.start_with?("custom_fields.") }
    end

    def custom_field_definitions
      @custom_field_definitions ||= if CUSTOM_FIELD_ENTITIES.include?(@entity)
        CustomFieldDefinition.for_resource(@entity).index_by(&:key)
      else
        {}
      end
    end

    def nested_attributes(flat)
      flat.each_with_object({}) do |(target, value), attributes|
        if target.start_with?("custom_fields.")
          attributes["custom_fields"] ||= {}
          converted = convert_value(target, value)
          attributes["custom_fields"][target.delete_prefix("custom_fields.")] = converted unless converted == :unmapped
        else
          attributes[target] = value
        end
      end
    end

    def preview_unmapped_values(sample)
      result = ENUMS.fetch(@entity, {}).each_with_object({}) do |(field, enum), result|
        source = @mapping[field]
        next unless source
        values = sample.map { |row| row[source] }.compact.uniq
        unknown = values.reject do |value|
          mapped = @value_maps.fetch(field, {}).fetch(value.to_s, value)
          enum.key?(mapped.to_s)
        end
        result[field] = unknown if unknown.any?
      end
      custom_field_targets(@mapping.keys).each do |target|
        definition = custom_field_definitions[target.delete_prefix("custom_fields.")]
        next unless definition

        source = @mapping[target]
        unknown = sample.filter_map { |row| row[source] }.uniq.reject do |value|
          converted = definition.field_type_multi_select? ? value.to_s.split(/[;,]/).map(&:strip) : value
          CustomFields::Type.coerce(definition, converted).valid?
        end
        result[target] = unknown if unknown.any?
      end
      result
    end

    def feature_enabled?
      feature = if %w[cases contacts organisations].include?(@entity)
        "service_desk"
      elsif @entity == "work_items"
        "work"
      elsif %w[leads deals].include?(@entity)
        "crm"
      end
      feature.nil? || Features.enabled?(feature)
    end

    def feature_error
      @result.error!("the #{@entity} module is not enabled for this tenant")
      @result
    end
  end
end
