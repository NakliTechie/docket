module Sprints
  # Closing a sprint has to decide what happens to work that didn't finish.
  # Unfinished items go to the backlog by default, or roll forward into a named
  # sprint. Finished work stays put — a closed sprint is the historical record
  # velocity is computed from, so moving done items out would falsify it.
  class Closeout
    def self.call(...) = new(...).call

    def initialize(sprint:, roll_to: nil)
      @sprint = sprint
      @roll_to = roll_to
    end

    def call
      raise ArgumentError, "sprint is already closed" if @sprint.status_closed?

      if @roll_to
        raise ArgumentError, "cannot roll work into the sprint being closed" if @roll_to == @sprint
        raise ArgumentError, "roll_to must be in the same project" if @roll_to.project_id != @sprint.project_id
        # Rolling into a CLOSED sprint would add work to a finished record and
        # retroactively change the velocity already reported for it.
        raise ArgumentError, "cannot roll work into a closed sprint" if @roll_to.status_closed?
      end

      moved = 0
      carried = []
      ActiveRecord::Base.transaction do
        @sprint.work_items.includes(:workflow_state).find_each do |item|
          next if item.done?

          carried << item.id
          item.update!(sprint: @roll_to)
          moved += 1
        end
        # Remember what left: it still counts as what this sprint committed to.
        @sprint.update!(status: :closed, rolled_out_item_ids: carried)
      end
      moved
    end
  end
end
