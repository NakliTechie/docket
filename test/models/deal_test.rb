require "test_helper"

class DealTest < ActiveSupport::TestCase
  setup do
    @pipeline = Pipeline.new(name: "Test Funnel")
    @pipeline.pipeline_stages.build([
      { name: "New", position: 0 },
      { name: "Won", position: 1, is_won: true },
      { name: "Lost", position: 2, is_lost: true }
    ])
    @pipeline.save!
    @new_stage, @won_stage, @lost_stage = @pipeline.pipeline_stages.order(:position).to_a
  end

  test "new deals default to the pipeline's first stage and open status" do
    deal = Deal.create!(name: "Opp", pipeline: @pipeline)
    assert_equal @new_stage, deal.pipeline_stage
    assert deal.status_open?
  end

  test "value reads/writes rupees against the cents column" do
    deal = Deal.new(name: "x", pipeline: @pipeline, value: 2500.75)
    assert_equal 250_075, deal.value_cents
    assert_in_delta 2500.75, deal.value, 0.001
  end

  test "moving to a won stage derives won status and stamps closed_at" do
    deal = Deal.create!(name: "Winner", pipeline: @pipeline)
    deal.move_to_stage!(@won_stage)
    assert deal.reload.status_won?
    assert deal.closed_at.present?
  end

  test "moving to a lost stage derives lost; back to open clears closed_at" do
    deal = Deal.create!(name: "Mover", pipeline: @pipeline)
    deal.move_to_stage!(@lost_stage)
    assert deal.status_lost?
    deal.move_to_stage!(@new_stage)
    assert deal.status_open?
    assert_nil deal.closed_at
  end

  test "a stage from another pipeline is rejected" do
    other = Pipeline.new(name: "Other")
    other.pipeline_stages.build(name: "Solo", position: 0)
    other.save!
    deal = Deal.new(name: "Bad", pipeline: @pipeline, pipeline_stage: other.pipeline_stages.first)
    assert_not deal.valid?
    assert deal.errors[:pipeline_stage].any?
  end
end
