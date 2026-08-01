module Imports
  # Jira Cloud/Data Center migration adapter. Source keys are durable identity;
  # status and role mappings are explicit; re-imports preserve local edits as
  # conflicts instead of silently overwriting them.
  class Jira
    DEFAULT_STATUS_MAP = {
      "backlog" => "Backlog", "to do" => "Todo", "todo" => "Todo", "open" => "Todo",
      "selected for development" => "Todo",
      "in progress" => "In progress", "in development" => "In progress",
      "in review" => "In review", "code review" => "In review", "review" => "In review",
      "done" => "Done", "closed" => "Done", "resolved" => "Done"
    }.freeze
    TYPE_MAP = {
      "bug" => :bug, "story" => :story, "task" => :task, "sub-task" => :task,
      "subtask" => :task, "epic" => :epic, "improvement" => :story,
      "new feature" => :story
    }.freeze
    PRIORITY_MAP = {
      "highest" => :urgent, "blocker" => :urgent, "critical" => :urgent,
      "high" => :high, "major" => :high, "medium" => :normal, "normal" => :normal,
      "low" => :low, "lowest" => :low, "minor" => :low, "trivial" => :low
    }.freeze
    ISSUE_FIELDS = %w[id key self expand fields changelog renderedFields names schema].freeze
    FIELDS = %w[
      summary description issuetype priority status timeoriginalestimate
      aggregatetimeoriginalestimate duedate reporter assignee creator labels comment attachment
      created updated resolutiondate statuscategorychangedate project parent sprint
      environment components fixVersions versions resolution watches subtasks
    ].freeze
    USER_FIELDS = %w[
      accountId key name displayName emailAddress active accountType role projectRoles avatarUrls self
      timeZone locale
    ].freeze
    COMMENT_FIELDS = %w[id body author updateAuthor created updated self jsdPublic].freeze

    def self.call(...) = new(...).call

    def initialize(payload: nil, file: nil, source: nil, project: nil, status_map: {},
                   role_map: {}, custom_field_map: {}, dry_run: false, actor: nil, source_instance: "default",
                   resume_token: nil, batch_size: 200)
      @result = Result.new
      @input = Input.new(payload: payload, file: file, source: source, bare_entity: "issues")
      @source = source
      @export_root = File.dirname(File.expand_path(file)) if file
      @project = project
      @status_map = DEFAULT_STATUS_MAP.merge(
        status_map.to_h.transform_keys { |key| key.to_s.downcase }
      )
      @role_map = role_map.stringify_keys
      @touched_projects = Set.new
      @dry_run = dry_run
      @actor = actor
      @source_instance = source_instance
      @resume_token = resume_token
      @batch_size = batch_size
      @custom_field_mapping = CustomFields::ImportMapping.new(
        resource_type: "work_items", mapping: custom_field_map, result: @result
      )
    rescue JsonRows::FormatError, ArgumentError => e
      @result.error!(e.message)
    end

    def call
      return @result if @result.errors.any?
      unless Features.enabled?("work")
        @result.error!("the work module is not enabled for this tenant")
        return @result
      end

      @session = Session.new(source: "jira", source_instance: @source_instance,
                             dry_run: @dry_run, resume_token: @resume_token,
                             batch_size: @batch_size, result: @result)
      @source.watermark = @session.run.previous_watermark if @source&.respond_to?(:watermark=)
      @attachments = Attachments.new(session: @session, downloader: @source,
                                     export_root: @export_root)
      @session.process(@input.rows("users", optional: true), stream: "users") do |row|
        import_user(row)
      end
      cursor = ->(row) { @source.cursor_for("issues", row) } if @source
      @session.process(@input.rows("issues"), stream: "issues", cursor: cursor) do |row|
        import_issue(row)
      end
      @session.finish!
      @session.result
    rescue JsonRows::FormatError, Session::ResumeError, ActiveRecord::RecordNotFound => e
      @result.error!(e.message)
      @result
    ensure
      reset_dry_run_associations
    end

    private

    def import_issue(issue)
      return invalid_row("issue", issue) unless issue.is_a?(Hash)

      FieldContract.new(@session.result, "issue", ISSUE_FIELDS).inspect!(issue)
      fields = issue["fields"] || {}
      return invalid_row("issue fields", fields) unless fields.is_a?(Hash)

      FieldContract.new(@session.result, "issue.fields",
                        FIELDS + @custom_field_mapping.consumed_sources).inspect!(fields)
      key = issue["key"].to_s
      return @session.result.skip!("issues") if key.blank?

      project = @project || project_for(key, fields)
      return @session.result.skip!("issues") if project.nil?
      @touched_projects << project

      state = state_for(project, fields, key)
      return @session.result.skip!("issues") if fields.dig("status", "name").present? && state.nil?

      existing = @session.identity_target("issue", key)
      existing ||= project.work_items.find_by(source_key: key)
      number = available_number(project, key, existing)
      attributes = issue_attributes(issue, fields, project, state, existing)
      item = @session.sync(source_type: "issue", external_id: key, kind: "issues",
                           attributes: attributes, source_updated_at: fields["updated"],
                           existing: existing) do
        WorkItem.new(project: project, number: number, source_key: key)
      end
      import_comments(item, fields)
      @attachments.import(record: item, rows: fields["attachment"],
                          parent_external_id: key, source_type: "issue_attachment")
    rescue ActiveRecord::RecordInvalid => e
      @session.result.error!("#{key.presence || 'issue'}: #{e.record.errors.full_messages.to_sentence}")
    end

    def issue_attributes(issue, fields, project, state, existing)
      key = issue["key"].to_s
      attributes = { "project_id" => project.id, "source_key" => key }
      attributes["title"] = fields["summary"].presence || key if fields.key?("summary") || existing.nil?
      attributes["description"] = description_for(fields, key) if fields.key?("description")
      attributes["workflow_state_id"] = state.id if state
      if fields.key?("issuetype")
        mapped = mapped_value(TYPE_MAP, :issue_type, fields.dig("issuetype", "name"), key)
        attributes["kind"] = mapped if mapped
      end
      if fields.key?("priority")
        mapped = mapped_value(PRIORITY_MAP, :priority, fields.dig("priority", "name"), key)
        attributes["priority"] = mapped if mapped
      end
      attributes["estimate"] = estimate_for(fields) if fields.key?("timeoriginalestimate") ||
                                                       fields.key?("aggregatetimeoriginalestimate")
      attributes["due_on"] = parse_date(fields["duedate"]) if fields.key?("duedate")
      attributes["labels"] = Array(fields["labels"]).compact if fields.key?("labels")
      attributes["assignee_id"] = user_for(fields["assignee"], context: "assignee")&.id if fields.key?("assignee")
      attributes["reporter_id"] = user_for(fields["reporter"], context: "reporter")&.id if fields.key?("reporter")
      attributes["reporter_id"] ||= @actor&.id if existing.nil?
      attributes["created_at"] = parse_time(fields["created"]) if fields.key?("created")
      attributes["updated_at"] = parse_time(fields["updated"]) if fields.key?("updated")
      mapped_custom_fields = @custom_field_mapping.values(fields)
      if mapped_custom_fields.any?
        attributes["custom_fields"] = existing&.custom_fields.to_h.merge(mapped_custom_fields) || mapped_custom_fields
      end
      if state&.category_done?
        attributes["closed_at"] = parse_time(fields["resolutiondate"] ||
                                              fields["statuscategorychangedate"])
        if attributes["closed_at"].nil?
          @session.result.unmapped!("missing_resolution_timestamp", key)
        end
      elsif state
        attributes["closed_at"] = nil
      end
      attributes
    end

    def project_for(key, fields)
      source_key = fields.dig("project", "key").presence || key.split("-").first.to_s.upcase
      return if source_key.blank?

      Project.find_or_create_by!(key: source_key) do |project|
        project.name = fields.dig("project", "name").presence || source_key.titleize
      end
    rescue ActiveRecord::RecordInvalid => e
      @session.result.error!("#{key}: #{e.record.errors.full_messages.to_sentence}")
      nil
    end

    def state_for(project, fields, key)
      source = fields.dig("status", "name").to_s
      return project.default_state if source.blank?

      target = @status_map[source.downcase]
      if target.nil?
        @session.result.unmapped!("status", source)
        @session.result.error!("#{key}: status #{source.inspect} has no mapping")
        return
      end
      state = project.workflow_states.find_by("LOWER(name) = ?", target.downcase)
      return state if state

      @session.result.unmapped!("target_status", target)
      @session.result.error!("#{key}: mapped state #{target.inspect} does not exist in #{project.key}")
      nil
    end

    def available_number(project, key, existing)
      return existing.number if existing

      number = key.split("-").last.to_i
      return unless number.positive?
      return if project.work_items.with_deleted.exists?(number: number)

      number
    end

    def import_comments(item, fields)
      enumerable(fields.dig("comment", "comments")).each do |comment|
        next invalid_row("comment", comment) unless comment.is_a?(Hash)

        FieldContract.new(@session.result, "comment", COMMENT_FIELDS).inspect!(comment)
        body = comment["body"]
        body = body.is_a?(Hash) ? adf_to_text(body) : body.to_s
        next @session.result.skip!("comments") if body.blank?

        source_id = comment["id"].presence || Digest::SHA256.hexdigest(
          [ item.source_key, comment["created"], body ].join("\0")
        )
        author = comment["author"].present? ?
          user_for(comment["author"], context: "comment_author") : @actor
        source_name = profile_name(comment["author"])
        source_name ||= @actor&.name
        if author.nil? && source_name.blank?
          @session.result.unmapped!("comment_author", "missing")
          @session.result.skip!("comments")
          next
        end
        attributes = {
          "work_item_id" => item.id, "body" => body,
          "author_type" => author&.class&.name,
          "author_id" => author&.id,
          "source_author_name" => author ? nil : source_name
        }
        attributes["created_at"] = parse_time(comment["created"]) if comment.key?("created")
        attributes["updated_at"] = parse_time(comment["updated"]) if comment.key?("updated")
        existing = @session.identity_target("comment", source_id.to_s)
        @session.sync(source_type: "comment", external_id: source_id, kind: "comments",
                      attributes: attributes, source_updated_at: comment["updated"],
                      existing: existing) { WorkComment.new }
      end
    end

    def import_user(profile)
      return invalid_row("user", profile) unless profile.is_a?(Hash)

      FieldContract.new(@session.result, "user", USER_FIELDS).inspect!(profile)
      external_id = user_identity(profile)
      return missing_user(profile) if external_id.blank?

      role = mapped_role(profile)
      if role.nil?
        @session.result.skip!("users")
        return
      end
      email = profile["emailAddress"].presence
      if email.nil?
        @session.result.unmapped!("user_email", external_id)
        @session.result.skip!("users")
        return
      end

      existing = @session.identity_target("user", external_id)
      existing ||= User.find_by(email_address: email)
      attributes = {
        "name" => profile_name(profile).presence || email.split("@").first,
        "email_address" => email
      }
      attributes["active"] = profile["active"] unless profile["active"].nil?
      attributes["role"] = role if existing.nil?
      @session.sync(source_type: "user", external_id: external_id, kind: "users",
                    attributes: attributes, source_updated_at: profile["updated"],
                    existing: existing, metadata: { "mapped_role" => role }) do
        User.new(password: SecureRandom.base64(48))
      end
    end

    def user_for(profile, context:)
      return if profile.blank?
      return profile if profile.is_a?(User)

      external_id = user_identity(profile)
      user = @session.identity_target("user", external_id)
      return user if user

      import_user(profile)
      @session.identity_target("user", external_id).tap do |resolved|
        @session.result.unmapped!(context, external_id) if resolved.nil?
      end
    end

    def mapped_role(profile)
      candidates = [ profile["role"], profile["accountType"],
                     *Array(profile["projectRoles"]), "default" ].compact.map(&:to_s)
      key = candidates.find { |candidate| @role_map.key?(candidate) }
      mapped = @role_map[key].to_s if key
      return mapped if User.roles.key?(mapped)

      candidates.reject { |candidate| candidate == "default" }.each do |candidate|
        @session.result.unmapped!("user_role", candidate)
      end
      nil
    end

    def user_identity(profile)
      return profile.to_s unless profile.is_a?(Hash)

      profile["accountId"].presence || profile["key"].presence || profile["name"].presence
    end

    def profile_name(profile)
      return if profile.blank?
      return profile.to_s unless profile.is_a?(Hash)

      profile["displayName"].presence || profile["name"].presence || profile["emailAddress"].presence
    end

    def mapped_value(mapping, field, value, key)
      source = value.to_s.downcase
      mapped = mapping[source]
      return mapped if mapped

      @session.result.unmapped!(field, value) if value.present?
      @session.result.error!("#{key}: #{field} #{value.inspect} has no mapping") if value.present?
      nil
    end

    def description_for(fields, key)
      body = fields["description"]
      body = body.is_a?(Hash) ? adf_to_text(body) : body.to_s
      [ body.presence, "Imported from Jira #{key}." ].compact.join("\n\n")
    end

    def adf_to_text(node)
      return node.to_s unless node.is_a?(Hash)
      return node["text"].to_s if node["type"] == "text"

      separator = node["type"] == "paragraph" ? "" : "\n"
      Array(node["content"]).map { |child| adf_to_text(child) }.join(separator)
    end

    def estimate_for(fields)
      seconds = fields["timeoriginalestimate"] || fields["aggregatetimeoriginalestimate"]
      return if seconds.blank?

      (seconds.to_f / 3600).round(2)
    end

    def parse_time(value)
      value.present? ? Time.zone.parse(value.to_s) : nil
    rescue ArgumentError
      @session.result.unmapped!("invalid_timestamp", value)
      nil
    end

    def parse_date(value)
      value.present? ? Date.parse(value.to_s) : nil
    rescue ArgumentError
      @session.result.unmapped!("invalid_date", value)
      nil
    end

    def invalid_row(type, row)
      @session.result.error!("#{type}: expected an object, got #{row.class}")
    end

    def missing_user(profile)
      @session.result.error!("user #{profile_name(profile).inspect}: stable source id is required")
    end

    def enumerable(value)
      value.is_a?(Array) || value.is_a?(Enumerator) ? value : Array(value)
    end

    def reset_dry_run_associations
      return unless @dry_run

      @touched_projects.each { |project| project.association(:work_items).reset }
    end
  end
end
