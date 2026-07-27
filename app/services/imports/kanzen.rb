module Imports
  # A KanZen board (.kanzen.json) -> a project. KanZen is the single-file
  # local-first kanban this board's UX is modelled on; teams that started there
  # shouldn't have to retype their work to move up to a multi-user deployment.
  #
  # Columns become workflow states (the LAST column is treated as done, which is
  # how a kanban board reads left-to-right), cards become work items, checklist
  # entries become child items, and card comments carry across.
  class Kanzen
    def self.call(...) = new(...).call

    def initialize(payload:, key: nil, dry_run: false, actor: nil)
      @result = Result.new
      @board = payload.is_a?(String) ? safe_parse(payload) : payload
      @key = key
      @dry_run = dry_run
      @actor = actor
    end

    def call
      return @result if @board.blank?

      ActiveRecord::Base.transaction do
        project = build_project
        states = build_states(project)
        import_cards(project, states)
        raise ActiveRecord::Rollback if @dry_run
      end
      @result
    end

    private

    def safe_parse(raw)
      JSON.parse(raw)
    rescue JSON::ParserError => e
      @result.error!("could not parse the board: #{e.message}")
      nil
    end

    def build_project
      title = @board["title"].presence || @board["name"].presence || "Imported board"
      key = (@key.presence || title).to_s.gsub(/[^A-Za-z0-9]/, "").upcase.first(10)
      key = "BOARD" if key.length < 2
      project = Project.find_or_initialize_by(key: key)
      project.name = title if project.new_record?
      project.save!
      @fresh_project = project.previously_new_record?
      @result.create!("projects") if @fresh_project
      project
    end

    def build_states(project)
      columns = Array(@board["columns"] || @board["lists"])
      return project.workflow_states.ordered.to_a if columns.empty?

      # Only a project THIS import created gets its columns replaced. Importing
      # into an existing project maps onto the columns already there — silently
      # restructuring a live board would strand its work items.
      unless @fresh_project
        return columns.map do |col|
          name = col["title"].presence || col["name"].presence
          found = project.workflow_states.find_by("LOWER(name) = ?", name.to_s.downcase)
          @result.unmapped!(:column, name) if found.nil?
          found || project.default_state
        end
      end

      # A kanban board reads left to right, so the last column is "done" and
      # the first is the intake. Everything between is work in progress.
      project.workflow_states.destroy_all
      columns.each_with_index.map do |col, index|
        category = if index == columns.size - 1 then :done
        elsif index.zero? then :todo
        else :in_progress
        end
        project.workflow_states.create!(name: col["title"].presence || col["name"].presence || "Column #{index + 1}",
                                        category: category, position: index,
                                        wip_limit: col["wipLimit"].presence || col["wip_limit"].presence)
      end
    end

    def import_cards(project, states)
      Array(@board["columns"] || @board["lists"]).each_with_index do |col, index|
        state = states[index] || project.default_state
        Array(col["cards"]).each do |card|
          title = card["title"].presence || card["name"].presence
          next @result.skip!("cards") if title.blank?
          next @result.skip!("cards") if project.work_items.exists?(title: title)

          item = project.work_items.create!(
            title: title,
            description: card["description"].presence || card["desc"].presence,
            workflow_state: state,
            priority: priority_for(card),
            due_on: parse_date(card["dueDate"] || card["due"]),
            reporter: @actor
          )
          @result.create!("cards")
          import_checklist(item, card, project, state)
          import_comments(item, card)
        end
      end
    end

    def priority_for(card)
      case card["priority"].to_s.downcase
      when "urgent", "highest" then :urgent
      when "high" then :high
      when "low" then :low
      else :normal
      end
    end

    def parse_date(value) = value.present? ? (Date.parse(value.to_s) rescue nil) : nil

    def import_checklist(parent, card, project, state)
      Array(card["checklist"] || card["checklists"]).each do |entry|
        text = entry.is_a?(Hash) ? entry["text"].presence || entry["title"].presence : entry.to_s
        next if text.blank?

        project.work_items.create!(title: text, parent: parent, workflow_state: state,
                                   kind: :task, reporter: @actor)
        @result.create!("checklist_items")
      end
    end

    def import_comments(item, card)
      author = @actor || User.staff.first
      return if author.nil?

      Array(card["comments"]).each do |comment|
        body = comment.is_a?(Hash) ? comment["text"].presence || comment["body"].presence : comment.to_s
        next if body.blank?

        item.work_comments.create!(body: body, author: author)
        @result.create!("comments")
      end
    end
  end
end
