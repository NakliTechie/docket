module Sprints
  # Sprint reporting, computed from the record rather than stored: completed
  # estimate per closed sprint (velocity), and cycle time from creation to the
  # move into a done column. A sibling of SalesReport/OperationalReport — it
  # holds the aggregation, the controller holds none.
  class Velocity
    def self.call(...) = new(...).call

    def initialize(project:, limit: 8)
      @project = project
      @limit = limit
    end

    def call
      sprints = @project.sprints.where(status: %i[active closed]).ordered.last(@limit)
      { sprints: sprints.map { |s| sprint_row(s) }, cycle_time_days: cycle_time_days }
    end

    private

    def sprint_row(sprint)
      # Items that were ROLLED OUT at close-out are still part of what the
      # sprint committed to — counting only what remains made every closed
      # sprint report 100% delivery against commitment, which is the one number
      # this report exists to contradict.
      items = WorkItem.with_deleted.where(sprint_id: sprint.id)
                      .or(WorkItem.with_deleted.where(id: sprint.rolled_out_item_ids))
                      .includes(:workflow_state).to_a
      done = items.select(&:done?)
      {
        sprint_id: sprint.id,
        name: sprint.name,
        status: sprint.status,
        committed: items.size,
        completed: done.size,
        # Velocity is completed ESTIMATE, not item count — five one-point items
        # and one thirteen-point item are not the same sprint.
        completed_estimate: done.sum { |i| i.estimate.to_f },
        committed_estimate: items.sum { |i| i.estimate.to_f }
      }
    end

    # Median, not mean: one item that sat open for six months would drag a mean
    # into uselessness.
    def cycle_time_days
      spans = @project.work_items.where.not(closed_at: nil)
                      .pluck(:created_at, :closed_at)
                      .map { |created, closed| ((closed - created) / 1.day).round(1) }
      return nil if spans.empty?

      sorted = spans.sort
      mid = sorted.size / 2
      sorted.size.odd? ? sorted[mid] : ((sorted[mid - 1] + sorted[mid]) / 2.0).round(1)
    end
  end
end
