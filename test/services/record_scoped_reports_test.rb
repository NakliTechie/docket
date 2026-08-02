require "test_helper"

class RecordScopedReportsTest < ActiveSupport::TestCase
  setup do
    @viewer = users(:client_admin)
    @other = users(:agent_b)
    @viewer.update!(record_read_scope: :owned, record_write_scope: :owned)
  end

  test "sales reports aggregate only visible deals and leads" do
    pipeline = Pipeline.new(name: "Scoped pipeline")
    pipeline.pipeline_stages.build(name: "Open", position: 0, probability: 25)
    pipeline.save!
    stage = pipeline.pipeline_stages.first
    Deal.create!(name: "Visible", pipeline: pipeline, pipeline_stage: stage,
                 owner: @viewer, value: 100)
    Deal.create!(name: "Hidden", pipeline: pipeline, pipeline_stage: stage,
                 owner: @other, value: 900)
    Lead.create!(name: "Visible lead", email: "visible-scope@example.com", owner: @viewer)
    Lead.create!(name: "Hidden lead", email: "hidden-scope@example.com", owner: @other)

    report = SalesReport.new(
      from: Date.current,
      to: Date.current,
      deal_scope: RecordVisibility.resolve(@viewer, Deal.with_deleted),
      lead_scope: RecordVisibility.resolve(@viewer, Lead.with_deleted)
    )

    assert_equal 1, report.stats[:open_deals]
    assert_equal({ "INR" => 10_000 }, report.stats[:open_values_by_currency])
    assert_equal 1, report.stats[:leads_created]
  end

  test "operational activity and satisfaction reports share the case boundary" do
    visible = cases(:pension_case)
    hidden = cases(:assigned_case)
    visible.update_columns(owner_id: @viewer.id, created_at: Time.current)
    hidden.update_columns(owner_id: @other.id, assignee_id: @other.id, created_at: Time.current)
    Message.create!(case: visible, body: "Visible reply", kind: :public_reply, direction: :outbound)
    Message.create!(case: hidden, body: "Hidden reply", kind: :public_reply, direction: :outbound)
    CsatSurvey.create!(case: visible, contact: visible.contact, invited_at: Time.current)
    CsatSurvey.create!(case: hidden, contact: hidden.contact, invited_at: Time.current)

    cases_scope = RecordVisibility.resolve(@viewer, Case.with_deleted)
    messages_scope = Message.with_deleted.where(case_id: cases_scope.select(:id))
    activity = ActivityReport.new(from: Date.current, to: Date.current,
                                  case_scope: cases_scope, message_scope: messages_scope)
    csat = CsatReport.new(from: Date.current, to: Date.current, case_scope: cases_scope)

    assert_equal 1, activity.stats[:cases_created]
    assert_equal 1, activity.stats[:human_replies]
    assert_equal 1, csat.as_json[:invitations]
  end

  test "decision visibility and quality follow each decision subject" do
    visible = cases(:pension_case)
    hidden = cases(:assigned_case)
    visible.update_column(:owner_id, @viewer.id)
    hidden.update_columns(owner_id: @other.id, assignee_id: @other.id)
    create_decision(visible, "visible")
    create_decision(hidden, "hidden")

    scope = RecordVisibility.resolve(@viewer, Decision.all)
    report = DecisionQualityReport.new(from: Date.current, to: Date.current,
                                       decision_scope: scope)

    assert_equal [ "visible" ], scope.pluck(:rule)
    assert_equal [ "visible" ], report.rows.map(&:rule)
    assert_equal scope.ids, DecisionPolicy::Scope.new(@viewer, Decision).resolve.ids
  end

  test "activity creation rejects a hidden subject" do
    visible = cases(:pension_case)
    hidden = cases(:assigned_case)
    visible.update_column(:owner_id, @viewer.id)
    hidden.update_columns(owner_id: @other.id, assignee_id: @other.id)

    assert ActivityPolicy.new(@viewer, Activity.new(subject: visible, title: "Call")).create?
    refute ActivityPolicy.new(@viewer, Activity.new(subject: hidden, title: "Call")).create?
  end

  private

  def create_decision(subject, rule)
    Decision.create!(
      subject: subject,
      rule: rule,
      version: "1",
      signal: "scope",
      decision_class: "confirm",
      recommendation: "Review",
      reasoning: "Record scope test",
      effect: "label"
    )
  end
end
