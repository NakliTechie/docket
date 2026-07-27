module Imports
  # Jira issues -> work items. Consumes a Jira REST search export
  # (`{"issues":[...]}`) or a plain array of issues, so it runs with no
  # credentials against a file the customer already has.
  #
  # Idempotent on the Jira key: re-running updates rather than duplicating, so
  # a failed migration can simply be run again.
  class Jira
    # Jira's default workflow, mapped onto the board columns a Docket project
    # seeds. Anything outside this is REPORTED, never guessed — a silently
    # mis-mapped status is worse than a named gap.
    DEFAULT_STATUS_MAP = {
      "backlog" => "Backlog", "to do" => "Todo", "todo" => "Todo", "open" => "Todo",
      "selected for development" => "Todo",
      "in progress" => "In progress", "in development" => "In progress",
      "in review" => "In review", "code review" => "In review", "review" => "In review",
      "done" => "Done", "closed" => "Done", "resolved" => "Done"
    }.freeze

    TYPE_MAP = {
      "bug" => :bug, "story" => :story, "task" => :task, "sub-task" => :task,
      "subtask" => :task, "epic" => :epic, "improvement" => :story, "new feature" => :story
    }.freeze

    PRIORITY_MAP = {
      "highest" => :urgent, "blocker" => :urgent, "critical" => :urgent,
      "high" => :high, "major" => :high,
      "medium" => :normal, "normal" => :normal,
      "low" => :low, "lowest" => :low, "minor" => :low, "trivial" => :low
    }.freeze

    def self.call(...) = new(...).call

    def initialize(payload:, project: nil, status_map: {}, dry_run: false, actor: nil)
      @result = Result.new
      @issues = extract_issues(payload)
      @project = project
      @status_map = DEFAULT_STATUS_MAP.merge(status_map.transform_keys { |k| k.to_s.downcase })
      @dry_run = dry_run
      @actor = actor
    end

    def call
      ActiveRecord::Base.transaction do
        @issues.each { |issue| import_issue(issue) }
        raise ActiveRecord::Rollback if @dry_run
      end
      @result
    end

    private

    def extract_issues(payload)
      data = payload.is_a?(String) ? JSON.parse(payload) : payload
      data.is_a?(Array) ? data : Array(data["issues"] || data[:issues])
    rescue JSON::ParserError => e
      @result.error!("could not parse the export: #{e.message}")
      []
    end

    def import_issue(issue)
      fields = issue["fields"] || {}
      key = issue["key"].to_s
      project = @project || project_for(key, fields)
      return @result.skip!("issues") if project.nil?

      state = state_for(project, fields)
      # Carry the Jira number across so JIRA-123 stays 123 here — the whole
      # point of the migration is that existing links and muscle memory survive.
      number = key.split("-").last.to_i
      item = project.work_items.with_deleted.find_by(number: number) if number.positive?
      existing = item.present?

      attrs = {
        title: fields["summary"].presence || key,
        description: description_for(fields, key),
        kind: TYPE_MAP.fetch(fields.dig("issuetype", "name").to_s.downcase) { report_unmapped(:issue_type, fields.dig("issuetype", "name")) || :task },
        priority: PRIORITY_MAP.fetch(fields.dig("priority", "name").to_s.downcase) { report_unmapped(:priority, fields.dig("priority", "name")) || :normal },
        workflow_state: state,
        estimate: estimate_for(fields),
        due_on: fields["duedate"].presence,
        reporter: @actor
      }

      item ||= project.work_items.new(number: number.positive? ? number : nil)
      item.assign_attributes(attrs)
      if item.save
        existing ? @result.update!("issues") : @result.create!("issues")
        import_comments(item, fields)
      else
        @result.error!("#{key}: #{item.errors.full_messages.to_sentence}")
      end
    end

    def project_for(key, _fields)
      prefix = key.split("-").first.to_s.upcase
      return nil if prefix.blank?

      Project.find_or_create_by!(key: prefix) { |p| p.name = prefix.titleize }
    end

    def state_for(project, fields)
      source = fields.dig("status", "name").to_s
      target = @status_map[source.downcase]
      if target.nil?
        report_unmapped(:status, source)
        return project.default_state
      end
      project.workflow_states.find_by("LOWER(name) = ?", target.downcase) || project.default_state
    end

    def description_for(fields, key)
      body = fields["description"]
      body = body.is_a?(Hash) ? adf_to_text(body) : body.to_s
      [ body.presence, "Imported from Jira #{key}." ].compact.join("\n\n")
    end

    # Jira Cloud returns Atlassian Document Format. Pull the text nodes rather
    # than dumping JSON into the description.
    def adf_to_text(node)
      return node["text"].to_s if node["type"] == "text"

      Array(node["content"]).map { |child| adf_to_text(child) }.join(node["type"] == "paragraph" ? "" : "\n")
    end

    def estimate_for(fields)
      seconds = fields["timeoriginalestimate"] || fields.dig("aggregatetimeoriginalestimate")
      return nil if seconds.blank?

      (seconds.to_f / 3600).round(2) # Jira stores seconds; we hold hours
    end

    def import_comments(item, fields)
      Array(fields.dig("comment", "comments")).each do |comment|
        body = comment["body"]
        body = body.is_a?(Hash) ? adf_to_text(body) : body.to_s
        next if body.blank? || item.work_comments.exists?(body: body)

        author = @actor || User.staff.first
        next if author.nil?

        item.work_comments.create!(body: body, author: author)
        @result.create!("comments")
      end
    end

    def report_unmapped(field, value)
      @result.unmapped!(field, value) if value.present?
      nil
    end
  end
end
