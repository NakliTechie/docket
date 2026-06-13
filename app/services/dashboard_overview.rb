# The operator landing dashboard: a thin facade composing the three report
# services (SalesReport, ActivityReport, OperationalReport) over one from..to
# window, plus a combined headline-KPI CSV export. Holds no aggregation logic of
# its own — each plane lives in its own service.
class DashboardOverview
  attr_reader :from, :to, :sales, :activity, :operational

  def initialize(from:, to:)
    @from = from
    @to = to
    @sales = SalesReport.new(from: from, to: to)
    @activity = ActivityReport.new(from: from, to: to)
    @operational = OperationalReport.new(from: from, to: to)
  end

  # Persisted decisioning history (the rule engine writes here when "run"; see
  # Decisioning::Dispatcher). Recent decisions, counts by lifecycle status, and
  # the parked confirm/of_record proposals awaiting a human.
  def decisions
    @decisions ||= Decision.recent_first.limit(15).to_a
  end

  def decision_summary
    @decision_summary ||= Decision.group(:status).count
                                  .transform_keys { |k| k.is_a?(Integer) ? Decision.statuses.key(k) : k.to_s }
  end

  def pending_confirmations
    @pending_confirmations ||= Decision.awaiting_confirmation.recent_first.to_a
  end

  # Headline KPIs across the four planes, one row each. All cells are fixed
  # labels or numbers (no user-supplied text), so no formula-injection guard is
  # needed here.
  def to_csv
    require "csv"
    a = activity.stats
    s = sales.stats
    sync = operational.sync_stats
    auto = operational.autonomy

    CSV.generate do |csv|
      csv << %w[section metric value from to]
      csv << row("cases", "created", a[:cases_created])
      csv << row("cases", "resolved", a[:cases_resolved])
      csv << row("cases", "resolution_rate_pct", a[:resolution_rate])
      csv << row("cases", "sla_breaches", a[:sla_breaches])
      csv << row("cases", "sla_at_risk", operational.sla_at_risk)
      csv << row("cases", "ai_replies", a[:agent_turns])
      csv << row("cases", "human_replies", a[:human_replies])

      csv << row("sales", "open_pipeline_rupees", rupees(s[:open_value_cents]))
      csv << row("sales", "weighted_forecast_rupees", rupees(s[:weighted_value_cents]))
      csv << row("sales", "won", s[:won_count])
      csv << row("sales", "win_rate_pct", s[:win_rate])

      csv << row("connectors", "sync_runs", sync[:runs])
      csv << row("connectors", "sync_success_rate_pct", sync[:success_rate])
      csv << row("connectors", "records_in", sync[:records_in])
      csv << row("connectors", "needing_attention", operational.connectors_needing_attention.size)

      csv << row("effector", "approval_queue_depth", operational.approval_queue_depth)
      csv << row("effector", "actions_succeeded", auto[:succeeded])
      csv << row("effector", "autonomy_rate_pct", auto[:autonomy_rate])
      csv << row("effector", "rejected", auto[:rejected])
    end
  end

  private

  def row(section, metric, value)
    [ section, metric, value, from, to ]
  end

  def rupees(cents)
    (cents || 0) / 100.0
  end
end
