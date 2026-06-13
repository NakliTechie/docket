# Operational analytics — the case-desk, connector-ingestion and
# effector-accountability planes the dashboard surfaces. A sibling to
# SalesReport / ActivityReport (NOT a replacement): it adds the metrics those
# two don't already compute, and DashboardOverview composes all three. Computed
# entirely from this deployment's own data — never transmitted anywhere.
#
# Two clocks, as in SalesReport:
#   * Snapshots (open-by-status, backlog age, SLA-at-risk, connector health,
#     approval-queue depth) are CURRENT — "what's true right now".
#   * Windowed figures (channel mix, created trend, sync + invocation volumes)
#     cover from..to, with_deleted where the row is soft-deletable (Case), so a
#     later soft-delete never rewrites past figures.
class OperationalReport
  attr_reader :from, :to

  def initialize(from:, to:)
    @from = from
    @to = to
  end

  def range
    from.beginning_of_day..to.end_of_day
  end

  # --- Case-desk plane -------------------------------------------------------

  # Snapshot: open cases grouped by status / priority / queue.
  def open_by_status
    @open_by_status ||= label_counts(Case.open_cases.group(:status).count, Case.statuses)
  end

  def open_by_priority
    @open_by_priority ||= label_counts(Case.open_cases.group(:priority).count, Case.priorities)
  end

  def open_by_queue
    @open_by_queue ||= begin
      counts = Case.open_cases.group(:queue_id).count
      queues = CaseQueue.with_deleted.where(id: counts.keys.compact).index_by(&:id)
      counts.map { |qid, count| { queue: queues[qid], count: count } }
            .sort_by { |row| -row[:count] }
    end
  end

  # Snapshot leading indicator: open, not-yet-breached cases whose resolution
  # deadline falls in the next 24h. Already-overdue ones are breaches, not risk.
  def sla_at_risk
    @sla_at_risk ||= Case.open_cases
                         .where(resolution_breached: false)
                         .where(resolution_due_at: Time.current..(Time.current + 24.hours))
                         .count
  end

  # Snapshot: how stale the open backlog is, bucketed by age.
  def backlog_age
    @backlog_age ||= begin
      now = Time.current
      buckets = { "under_1d" => 0, "1_3d" => 0, "3_7d" => 0, "over_7d" => 0 }
      Case.open_cases.pluck(:created_at).each do |created_at|
        age = now - created_at
        bucket = if age < 1.day then "under_1d"
        elsif age < 3.days then "1_3d"
        elsif age < 7.days then "3_7d"
        else "over_7d"
        end
        buckets[bucket] += 1
      end
      buckets
    end
  end

  # Windowed: cases created per channel.
  def channel_mix
    @channel_mix ||= label_counts(
      Case.with_deleted.where(created_at: range).group(:channel).count, Case.channels
    )
  end

  # Windowed: cases created per day across the window (sparkline series),
  # zero-filled so every day in from..to is present and ordered.
  def cases_created_trend
    @cases_created_trend ||= begin
      by_day = Case.with_deleted.where(created_at: range).pluck(:created_at)
                   .group_by { |t| t.to_date }.transform_values(&:size)
      (from..to).map { |date| { date: date, count: by_day[date] || 0 } }
    end
  end

  # --- Connector / ingestion plane ------------------------------------------

  # Windowed sync volume + success rate over ConnectorRun.
  def sync_stats
    @sync_stats ||= begin
      runs = ConnectorRun.where(created_at: range)
      total = runs.count
      success = runs.status_success.count
      {
        runs: total,
        success: success,
        failed: runs.status_failed.count,
        running: runs.status_running.count,
        success_rate: total.zero? ? nil : (success * 100.0 / total).round(1),
        records_in: runs.sum(:records_in),
        records_created: runs.sum(:records_created),
        records_updated: runs.sum(:records_updated)
      }
    end
  end

  # Snapshot: every connector with its status + freshness, name-ordered.
  def connector_health
    @connector_health ||= Connector.order(:name).map do |connector|
      { connector: connector, status: connector.status,
        last_synced_at: connector.last_synced_at, overdue: connector.due? }
    end
  end

  # Snapshot: the connectors an operator should look at — erroring, paused, or
  # overdue for a scheduled sync.
  def connectors_needing_attention
    @connectors_needing_attention ||= connector_health.select do |row|
      row[:overdue] || %w[error paused].include?(row[:status].to_s)
    end
  end

  # Snapshot: how many contacts each connector has sourced (provenance), biggest
  # first — the "value per connector" view unlocked by source_connector_id.
  def records_per_connector
    @records_per_connector ||= begin
      counts = Contact.where.not(source_connector_id: nil).group(:source_connector_id).count
      connectors = Connector.where(id: counts.keys).index_by(&:id)
      counts.map { |cid, count| { connector: connectors[cid], count: count } }
            .sort_by { |row| -row[:count] }
    end
  end

  # --- Effector / agent-accountability plane --------------------------------

  # Windowed agent-action volume per decision_class (autonomous/confirm/of_record).
  def invocations_by_decision_class
    @invocations_by_decision_class ||=
      ConnectorInvocation.where(created_at: range).group(:decision_class).count
                         .transform_keys { |k| k.to_s.presence || "unspecified" }
  end

  # Windowed agent-action volume per lifecycle status.
  def invocations_by_status
    @invocations_by_status ||= label_counts(
      ConnectorInvocation.where(created_at: range).group(:status).count, ConnectorInvocation.statuses
    )
  end

  # Snapshot: how many actions are currently parked awaiting a human.
  def approval_queue_depth
    @approval_queue_depth ||= ConnectorInvocation.status_proposed.count
  end

  # Windowed autonomy ratio: of the actions that succeeded, how many ran
  # unattended (no human approver) vs needed a human to approve.
  def autonomy
    @autonomy ||= begin
      succeeded = ConnectorInvocation.where(created_at: range).status_succeeded
      total = succeeded.count
      auto = succeeded.where(approved_by_id: nil).count
      {
        succeeded: total,
        auto_executed: auto,
        human_approved: total - auto,
        autonomy_rate: total.zero? ? nil : (auto * 100.0 / total).round(1),
        rejected: ConnectorInvocation.where(created_at: range).status_rejected.count
      }
    end
  end

  private

  # Group-count keys can come back as the raw integer or the enum label
  # depending on the adapter; normalise to the string label either way.
  def label_counts(counts, enum_map)
    inverse = enum_map.invert
    counts.each_with_object({}) do |(key, count), acc|
      label = key.is_a?(Integer) ? inverse[key] : key.to_s
      acc[label] = count if label
    end
  end
end
