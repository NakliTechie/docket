# The operator landing dashboard: a thin facade composing the three report
# services (SalesReport, ActivityReport, OperationalReport) over one from..to
# window, plus a combined headline-KPI CSV export. Holds no aggregation logic of
# its own — each plane lives in its own service.
class DashboardOverview
  attr_reader :from, :to, :sales, :activity, :operational

  def initialize(from:, to:)
    @from = from
    @to = to
    @sales = SalesReport.new(from: from, to: to) if Features.enabled?("crm")
    @activity = ActivityReport.new(from: from, to: to) if Features.enabled?("service_desk")
    @operational = OperationalReport.new(from: from, to: to)
  end

  # Persisted decisioning history (the rule engine writes here when "run"; see
  # Decisioning::Dispatcher). Recent decisions, counts by lifecycle status, and
  # the parked confirm/of_record proposals awaiting a human.
  def decisions
    return [] unless Features.enabled?("decisioning")

    @decisions ||= Decision.recent_first.limit(15).to_a
  end

  def decision_summary
    return {} unless Features.enabled?("decisioning")

    @decision_summary ||= Decision.group(:status).count
                                  .transform_keys { |k| k.is_a?(Integer) ? Decision.statuses.key(k) : k.to_s }
  end

  def pending_confirmations
    return [] unless Features.enabled?("decisioning")

    @pending_confirmations ||= Decision.awaiting_confirmation.recent_first.to_a
  end

  def decision_quality
    return [] unless Features.enabled?("decisioning")

    @decision_quality ||= DecisionQualityReport.new(from: from, to: to).rows
  end

  # Headline KPIs across the four planes, one row each. All cells are fixed
  # labels or numbers (no user-supplied text), so no formula-injection guard is
  # needed here.
  def to_csv
    require "csv"
    CSV.generate do |csv|
      csv << %w[section metric value currency from to]
      case_rows(csv) if Features.enabled?("service_desk")
      sales_rows(csv) if Features.enabled?("crm")
      connector_rows(csv) if Features.enabled?("connectors")
      decision_rows(csv) if Features.enabled?("decisioning")
    end
  end

  private

  def case_rows(csv)
    stats = activity.stats
    csv << row("cases", "created", stats[:cases_created])
    csv << row("cases", "resolved", stats[:cases_resolved])
    csv << row("cases", "resolution_rate_pct", stats[:resolution_rate])
    csv << row("cases", "sla_breaches", stats[:sla_breaches])
    csv << row("cases", "sla_at_risk", operational.sla_at_risk)
    csv << row("cases", "ai_replies", stats[:agent_turns])
    csv << row("cases", "human_replies", stats[:human_replies])
  end

  def sales_rows(csv)
    stats = sales.stats
    currency_rows(csv, "open_pipeline", stats[:open_values_by_currency])
    currency_rows(csv, "weighted_forecast", stats[:weighted_values_by_currency])
    csv << row("sales", "won", stats[:won_count])
    csv << row("sales", "win_rate_pct", stats[:win_rate])
  end

  def connector_rows(csv)
    sync = operational.sync_stats
    csv << row("connectors", "sync_runs", sync[:runs])
    csv << row("connectors", "sync_success_rate_pct", sync[:success_rate])
    csv << row("connectors", "records_in", sync[:records_in])
    csv << row("connectors", "needing_attention", operational.connectors_needing_attention.size)
  end

  def decision_rows(csv)
    auto = operational.autonomy
    csv << row("effector", "approval_queue_depth", operational.approval_queue_depth)
    csv << row("effector", "actions_succeeded", auto[:succeeded])
    csv << row("effector", "autonomy_rate_pct", auto[:autonomy_rate])
    csv << row("effector", "rejected", auto[:rejected])
    decision_quality.each do |quality|
      section = "decision_rule:#{quality.rule}"
      csv << row(section, "proposed", quality.proposed_count)
      csv << row(section, "approved", quality.approved_count)
      csv << row(section, "rejected", quality.rejected_count)
      csv << row(section, "overturned", quality.overturned_count)
      csv << row(section, "approval_rate_pct", quality.approval_rate)
      csv << row(section, "rejection_rate_pct", quality.rejection_rate)
      csv << row(section, "override_rate_pct", quality.override_rate)
    end
  end

  def row(section, metric, value)
    [ section, metric, value, nil, from, to ]
  end

  def decimal_value(cents)
    (cents || 0) / 100.0
  end

  def currency_rows(csv, metric, totals)
    if totals.empty?
      csv << [ "sales", metric, 0, nil, from, to ]
    else
      totals.each do |currency, cents|
        csv << [ "sales", metric, decimal_value(cents), currency, from, to ]
      end
    end
  end
end
