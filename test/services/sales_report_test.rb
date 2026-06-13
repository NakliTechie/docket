require "test_helper"

# SalesReport aggregates a deployment's own deal + lead data. Reset the two
# tables so each scenario asserts exact figures (the deals fixture is empty;
# leads ship fixtures that would otherwise land in the window).
class SalesReportTest < ActiveSupport::TestCase
  setup do
    Lead.unscoped.delete_all   # leads FK deals (converted_deal_id) — clear leads first
    Deal.unscoped.delete_all

    @pipeline = Pipeline.new(name: "Test Funnel")
    @pipeline.pipeline_stages.build([
      { name: "New", position: 0, probability: 10 },
      { name: "Qualified", position: 1, probability: 50 },
      { name: "Won", position: 2, probability: 100, is_won: true },
      { name: "Lost", position: 3, probability: 0, is_lost: true }
    ])
    @pipeline.save!
    @new, @qualified, @won, @lost = @pipeline.pipeline_stages.order(:position).to_a
    @rep = users(:agent_a)

    @from = 7.days.ago.to_date
    @to = Date.current
    @report = SalesReport.new(from: @from, to: @to)
  end

  def open_deal(stage, value, owner: nil)
    Deal.create!(name: "open", pipeline: @pipeline, pipeline_stage: stage, value: value, owner: owner)
  end

  # closed_at is auto-stamped to now on the terminal move; override it so the
  # deal lands inside or outside the report window deterministically.
  def closed_deal(stage, value, closed_at:, owner: nil)
    deal = Deal.create!(name: "closed", pipeline: @pipeline, pipeline_stage: stage, value: value, owner: owner)
    deal.update_column(:closed_at, closed_at)
    deal
  end

  def lost_with_reason(reason, value, closed_at:)
    deal = Deal.create!(name: "lost", pipeline: @pipeline, pipeline_stage: @lost, value: value, lost_reason: reason)
    deal.update_column(:closed_at, closed_at)
    deal
  end

  test "pipeline_by_stage sums open deals per stage, ordered down the funnel" do
    open_deal(@new, 1000)
    open_deal(@qualified, 2000)
    open_deal(@qualified, 3000)

    rows = @report.pipeline_by_stage
    assert_equal [ "New", "Qualified" ], rows.map { |r| r[:stage].name }
    assert_equal [ 1, 2 ], rows.map { |r| r[:count] }
    assert_equal [ 100_000, 500_000 ], rows.map { |r| r[:value_cents] }
  end

  test "weighted pipeline applies stage probability" do
    open_deal(@new, 1000)        # 100_000 * 0.10 = 10_000
    open_deal(@qualified, 2000)  # 200_000 * 0.50 = 100_000
    assert_equal 110_000, @report.weighted_pipeline_cents
  end

  test "won/lost are windowed by closed_at and drive the win rate" do
    closed_deal(@won, 5000, closed_at: 2.days.ago)
    closed_deal(@won, 1000, closed_at: 1.day.ago)
    closed_deal(@lost, 4000, closed_at: 3.days.ago)
    closed_deal(@won, 9999, closed_at: 30.days.ago) # outside the window — ignored

    stats = @report.stats
    assert_equal 2, stats[:won_count]
    assert_equal 600_000, stats[:won_value_cents]
    assert_equal 1, stats[:lost_count]
    assert_equal 400_000, stats[:lost_value_cents]
    assert_equal 66.7, stats[:win_rate]
  end

  test "lead conversion windows leads by created/converted" do
    Lead.create!(name: "A", email: "a@example.com") # created in window, not converted
    converted = Lead.create!(name: "B", email: "b@example.com")
    converted.update!(status: :converted, converted_at: 1.day.ago)

    stats = @report.stats
    assert_equal 2, stats[:leads_created]
    assert_equal 1, stats[:leads_converted]
    assert_equal 50.0, stats[:lead_conversion_rate]
  end

  test "loss_reasons breaks down lost deals by reason, windowed, most common first" do
    lost_with_reason(:price, 1000, closed_at: 1.day.ago)
    lost_with_reason(:price, 2000, closed_at: 2.days.ago)
    lost_with_reason(:competitor, 5000, closed_at: 3.days.ago)
    lost_with_reason(:price, 9999, closed_at: 30.days.ago) # outside the window — ignored
    closed_deal(@lost, 4000, closed_at: 1.day.ago)         # lost without a reason — excluded

    reasons = @report.loss_reasons
    assert_equal [ "price", "competitor" ], reasons.map { |r| r[:reason] }
    price = reasons.find { |r| r[:reason] == "price" }
    assert_equal 2, price[:count]
    assert_equal 300_000, price[:value_cents]
  end

  test "by_owner ranks reps by open + won value, skipping unassigned" do
    open_deal(@qualified, 1000)                                # unassigned — excluded
    closed_deal(@won, 5000, closed_at: 1.day.ago, owner: @rep) # 500_000 won (windowed)
    open_deal(@new, 2000, owner: @rep)                         # 200_000 open (snapshot)

    row = @report.by_owner.find { |r| r[:owner] == @rep }
    assert_equal 200_000, row[:open_value_cents]
    assert_equal 500_000, row[:won_value_cents]
    assert_equal [ @rep ], @report.by_owner.map { |r| r[:owner] } # the unassigned deal added no row
  end

  test "velocity reports avg days-to-win and audit-mined per-stage dwell over won deals" do
    t0 = 8.days.ago
    deal = nil
    travel_to(t0)          { deal = Deal.create!(name: "w", pipeline: @pipeline, pipeline_stage: @new, value: 5000) }
    travel_to(t0 + 3.days) { deal.update!(pipeline_stage: @qualified) }
    travel_to(2.days.ago)  { deal.update!(pipeline_stage: @won) } # terminal → won + auto-closes now

    v = @report.velocity
    assert_equal 1, v[:won_count]
    assert_in_delta 6.0, v[:avg_days_to_win], 0.3 # created 8d ago, closed 2d ago
    # the stages it dwelt in are reconstructed from the audit log
    assert_includes v[:stage_dwell].map { |row| row[:stage]&.name }, "New"
    assert_includes v[:stage_dwell].map { |row| row[:stage]&.name }, "Qualified"
  end
end
