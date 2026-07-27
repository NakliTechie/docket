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
      moved = 0
      ActiveRecord::Base.transaction do
        @sprint.work_items.includes(:workflow_state).find_each do |item|
          next if item.done?

          item.update!(sprint: @roll_to)
          moved += 1
        end
        @sprint.update!(status: :closed)
      end
      moved
    end
  end
end
