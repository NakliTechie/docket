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

      unless Features.enabled?("work")
        @result.error!("the work module is not enabled for this tenant")
        return @result
      end

      Mode.run do
        ActiveRecord::Base.transaction do
        project = build_project
        states = build_states(project)
        import_cards(project, states)
          raise ActiveRecord::Rollback if @dry_run
        end
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
        Array(col["cards"]).each_with_index do |card, card_index|
          title = card["title"].presence || card["name"].presence
          next @result.skip!("cards") if title.blank?
          source_key = card_source_key(col, index, card, card_index)
          item = project.work_items.find_or_initialize_by(source_key: source_key)
          was_new = item.new_record?
          attributes = { title: title, workflow_state: state, priority: priority_for(card) }
          if card.key?("description") || card.key?("desc")
            attributes[:description] = card["description"].presence || card["desc"].presence
          end
          attributes[:due_on] = parse_date(card["dueDate"] || card["due"]) if card.key?("dueDate") || card.key?("due")
          attributes[:reporter] = @actor if was_new
          item.assign_attributes(attributes)
          item.save!
          was_new ? @result.create!("cards") : @result.update!("cards")
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
      Array(card["checklist"] || card["checklists"]).each_with_index do |entry, index|
        text = entry.is_a?(Hash) ? entry["text"].presence || entry["title"].presence : entry.to_s
        next if text.blank?

        entry_id = entry.is_a?(Hash) ? entry["id"].presence : nil
        source_key = "#{parent.source_key}:checklist:#{entry_id || index}"
        item = project.work_items.find_or_initialize_by(source_key: source_key)
        was_new = item.new_record?
        item.assign_attributes(title: text, parent: parent, workflow_state: state,
                               kind: :task, reporter: @actor)
        item.save!
        was_new ? @result.create!("checklist_items") : @result.update!("checklist_items")
      end
    end

    def import_comments(item, card)
      author = @actor || User.staff.first
      return if author.nil?

      Array(card["comments"]).each do |comment|
        body = comment.is_a?(Hash) ? comment["text"].presence || comment["body"].presence : comment.to_s
        next if body.blank?

        if item.work_comments.exists?(body: body)
          @result.skip!("comments")
        else
          item.work_comments.create!(body: body, author: author)
          @result.create!("comments")
        end
      end
    end

    def card_source_key(column, column_index, card, card_index)
      board_id = @board["id"].presence || @board["uuid"].presence || @key.presence ||
                 @board["title"].presence || @board["name"].presence || "board"
      card_id = card["id"].presence || card["uuid"].presence
      unless card_id
        @result.unmapped!(:unstable_card_identity, "column #{column_index + 1} card #{card_index + 1}")
        column_id = column["id"].presence || column["uuid"].presence || column_index
        card_id = "#{column_id}:#{card_index}"
      end
      "kanzen:#{Digest::SHA256.hexdigest([ board_id, card_id ].join("\0"))[0, 32]}"
    end
  end
end
