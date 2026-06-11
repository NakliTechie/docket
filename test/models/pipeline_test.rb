require "test_helper"

class PipelineTest < ActiveSupport::TestCase
  def build_pipeline(name: "Sales Test")
    p = Pipeline.new(name: name)
    p.pipeline_stages.build([
      { name: "New", position: 0 },
      { name: "Won", position: 1, is_won: true },
      { name: "Lost", position: 2, is_lost: true }
    ])
    p
  end

  test "generates a slug and requires at least one stage" do
    p = build_pipeline
    assert p.save
    assert_equal "sales-test", p.slug

    empty = Pipeline.new(name: "Empty")
    assert_not empty.valid?
    assert empty.errors[:base].any?
  end

  test "first_stage is the lowest position; default is the first active pipeline" do
    p = build_pipeline
    p.save!
    assert_equal "New", p.first_stage.name
    assert_equal p, Pipeline.default if Pipeline.where.not(id: p.id).none?
  end

  test "a stage cannot be both won and lost" do
    stage = PipelineStage.new(name: "X", is_won: true, is_lost: true, pipeline: build_pipeline.tap(&:save!))
    assert_not stage.valid?
  end

  test "soft-deleting a pipeline keeps its stages" do
    p = build_pipeline
    p.save!
    stage_ids = p.pipeline_stages.map(&:id)
    p.destroy
    assert stage_ids.all? { |id| PipelineStage.exists?(id) }
  end
end
