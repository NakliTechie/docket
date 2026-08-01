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

  # H26: a nested "Remove" checkbox (allow_destroy) on a pipeline stage 500'd.
  # The stage is Audited + SoftDeletable; destroying it during nested autosave
  # appends an audit entry whose auditable is the stage — soft-deleted (hidden by
  # default scope) and marked_for_destruction — which the old required
  # belongs_to :auditable rejected as "must exist". AuditEntry now records the
  # reference by id/type, so the removal completes. (The forward pass blamed a
  # missing @destroyed on SoftDeletable#destroy; a probe showed that made no
  # difference — the collection drops the stage either way; the audit chain was
  # the real blocker.)
  test "a nested allow_destroy removal soft-deletes a stage" do
    p = build_pipeline
    p.save!
    stage = p.pipeline_stages.order(:position).last
    assert_equal 3, p.pipeline_stages.count

    p.update!(pipeline_stages_attributes: [ { id: stage.id, _destroy: "1" } ])

    assert PipelineStage.only_deleted.exists?(stage.id), "the removed stage is soft-deleted"
    refute_includes p.reload.pipeline_stages.map(&:id), stage.id, "and dropped from the collection"
    assert_equal 2, p.pipeline_stages.count
  end

  test "live deals block stage and pipeline removal" do
    pipeline = build_pipeline(name: "Live deals")
    pipeline.save!
    stage = pipeline.pipeline_stages.first
    Deal.create!(name: "Do not strand", pipeline: pipeline, pipeline_stage: stage)

    refute stage.destroy
    assert stage.errors[:base].any?
    refute pipeline.destroy
    assert pipeline.errors[:base].any?
  end
end
