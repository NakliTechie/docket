require "test_helper"

# DealStageHistory reconstructs a deal's stage timeline from the hash-chained
# audit log (no dedicated transition table). travel_to lets each stage move land
# at a distinct audit timestamp so dwell is measurable.
class DealStageHistoryTest < ActiveSupport::TestCase
  setup do
    @pipeline = Pipeline.new(name: "History Funnel")
    @pipeline.pipeline_stages.build([
      { name: "New", position: 0, probability: 10 },
      { name: "Qualified", position: 1, probability: 50 },
      { name: "Proposal", position: 2, probability: 70 }
    ])
    @pipeline.save!
    @new, @qualified, @proposal = @pipeline.pipeline_stages.order(:position).to_a
  end

  test "reconstructs stage segments with dwell from the audit log" do
    t0 = Time.utc(2026, 6, 1, 9, 0, 0)
    deal = nil
    travel_to(t0)            { deal = Deal.create!(name: "d", pipeline: @pipeline, pipeline_stage: @new, value: 1000) }
    travel_to(t0 + 2.days)   { deal.update!(pipeline_stage: @qualified) }
    travel_to(t0 + 5.days)   { deal.update!(pipeline_stage: @proposal) }

    segments = DealStageHistory.new(deal).segments
    assert_equal [ @new.id, @qualified.id, @proposal.id ], segments.map(&:stage_id)
    assert_in_delta 2 * 86_400, segments[0].dwell_seconds, 1
    assert_in_delta 3 * 86_400, segments[1].dwell_seconds, 1
    # Still in Proposal (deal not closed) → open spell, dwell measured to "now".
    assert segments[2].open?
  end

  test "an update that does not move the stage is not a transition" do
    t0 = Time.utc(2026, 6, 1, 9, 0, 0)
    deal = nil
    travel_to(t0)          { deal = Deal.create!(name: "d", pipeline: @pipeline, pipeline_stage: @new, value: 1000) }
    travel_to(t0 + 1.day)  { deal.update!(value: 2000) } # no stage change
    travel_to(t0 + 2.days) { deal.update!(pipeline_stage: @qualified) }

    segments = DealStageHistory.new(deal).segments
    assert_equal [ @new.id, @qualified.id ], segments.map(&:stage_id)
    assert_in_delta 2 * 86_400, segments[0].dwell_seconds, 1 # New → Qualified spans the value-only edit
  end

  test "a deal that never moved has a single open segment" do
    deal = Deal.create!(name: "d", pipeline: @pipeline, pipeline_stage: @new, value: 1000)
    segments = DealStageHistory.new(deal).segments
    assert_equal [ @new.id ], segments.map(&:stage_id)
    assert segments.first.open?
  end
end
