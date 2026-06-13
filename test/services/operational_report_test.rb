require "test_helper"

# OperationalReport — case-desk snapshots, connector-ingestion volume/health,
# and effector-accountability. Case tables are fixture-populated, so case-desk
# assertions check deltas; the connector_runs / connector_invocations tables
# start empty, so those planes are asserted absolutely.
class OperationalReportTest < ActiveSupport::TestCase
  def report(from: 30.days.ago.to_date, to: Date.current)
    OperationalReport.new(from: from, to: to)
  end

  # --- Case-desk plane ---

  test "open_by_status counts only open cases and uses string labels" do
    before = report.open_by_status["in_progress"].to_i
    kase = Case.create!(subject: "Live one", contact: contacts(:asha))
    kase.update_columns(status: Case.statuses["in_progress"])
    assert_equal before + 1, report.open_by_status["in_progress"]
    # a resolved case is not "open"
    kase.update_columns(status: Case.statuses["resolved"])
    assert_equal before, report.open_by_status["in_progress"]
  end

  test "sla_at_risk counts open, not-breached cases due within 24h but not the overdue ones" do
    before = report.sla_at_risk
    at_risk = Case.create!(subject: "Due soon", contact: contacts(:asha))
    at_risk.update_columns(status: Case.statuses["in_progress"], resolution_breached: false,
                           resolution_due_at: 6.hours.from_now)
    overdue = Case.create!(subject: "Already late", contact: contacts(:asha))
    overdue.update_columns(status: Case.statuses["in_progress"], resolution_breached: false,
                           resolution_due_at: 2.hours.ago)
    assert_equal before + 1, report.sla_at_risk
  end

  test "backlog_age buckets open cases by age and channel_mix windows by created_at" do
    fresh = Case.create!(subject: "Backlog", contact: contacts(:asha), channel: :phone)
    fresh.update_columns(status: Case.statuses["new"], created_at: 5.days.ago)
    r = report
    assert_operator r.backlog_age["3_7d"], :>=, 1
    assert_operator r.channel_mix["phone"].to_i, :>=, 1
  end

  test "cases_created_trend is a zero-filled daily series spanning the window" do
    r = report(from: 7.days.ago.to_date, to: Date.current)
    assert_equal 8, r.cases_created_trend.length # inclusive range
    assert_equal r.from, r.cases_created_trend.first[:date]
    assert_equal r.to, r.cases_created_trend.last[:date]
    assert(r.cases_created_trend.all? { |d| d[:count].is_a?(Integer) })
  end

  # --- Connector / ingestion plane ---

  def connector(status: :active, last_synced_at: nil, interval: nil)
    Connector.create!(name: "Sync #{SecureRandom.hex(3)}", provider: "http_json", target: "contacts",
                      field_mapping: { "external_id" => "id" }, status: status,
                      last_synced_at: last_synced_at, schedule_interval_minutes: interval)
  end

  test "sync_stats aggregates run volume, success rate and records" do
    c = connector
    ConnectorRun.create!(connector: c, status: :success, records_in: 10, records_created: 4, records_updated: 6)
    ConnectorRun.create!(connector: c, status: :success, records_in: 5, records_created: 5, records_updated: 0)
    ConnectorRun.create!(connector: c, status: :failed)
    s = report.sync_stats
    assert_equal 3, s[:runs]
    assert_equal 2, s[:success]
    assert_equal 1, s[:failed]
    assert_equal 66.7, s[:success_rate]
    assert_equal 15, s[:records_in]
    assert_equal 9, s[:records_created]
  end

  test "connector_health snapshots status + freshness and flags those needing attention" do
    connector(status: :active)
    connector(status: :error)
    # active + scheduled + never synced → overdue (due?)
    connector(status: :active, interval: 60, last_synced_at: nil)
    health = report.connector_health
    assert_equal 3, health.length
    attention = report.connectors_needing_attention
    # the error connector + the overdue one
    assert_equal 2, attention.length
    assert(attention.any? { |row| row[:status].to_s == "error" })
    assert(attention.any? { |row| row[:overdue] })
  end

  # --- Effector / accountability plane ---

  def invocation(decision_class:, status:, approved_by: nil, action: "send")
    ConnectorInvocation.create!(connector: @conn ||= connector, action: action,
                                decision_class: decision_class, status: status, approved_by: approved_by)
  end

  test "invocations_by_decision_class and _by_status window agent actions" do
    invocation(decision_class: "autonomous", status: :succeeded)
    invocation(decision_class: "confirm", status: :succeeded, approved_by: users(:admin))
    invocation(decision_class: "of_record", status: :proposed)
    by_dc = report.invocations_by_decision_class
    assert_equal 1, by_dc["autonomous"]
    assert_equal 1, by_dc["confirm"]
    assert_equal 1, by_dc["of_record"]
    by_status = report.invocations_by_status
    assert_equal 2, by_status["succeeded"]
    assert_equal 1, by_status["proposed"]
  end

  test "approval_queue_depth is a snapshot of proposed actions" do
    assert_equal 0, report.approval_queue_depth
    invocation(decision_class: "confirm", status: :proposed)
    invocation(decision_class: "of_record", status: :proposed)
    invocation(decision_class: "autonomous", status: :succeeded)
    assert_equal 2, report.approval_queue_depth
  end

  test "autonomy ratio splits succeeded actions into unattended vs human-approved" do
    invocation(decision_class: "autonomous", status: :succeeded) # no approver → auto
    invocation(decision_class: "autonomous", status: :succeeded) # no approver → auto
    invocation(decision_class: "confirm", status: :succeeded, approved_by: users(:admin)) # human
    invocation(decision_class: "confirm", status: :rejected)
    a = report.autonomy
    assert_equal 3, a[:succeeded]
    assert_equal 2, a[:auto_executed]
    assert_equal 1, a[:human_approved]
    assert_equal 66.7, a[:autonomy_rate]
    assert_equal 1, a[:rejected]
  end
end
