require "test_helper"

class DeliverablesTest < ActiveSupport::TestCase
  setup do
    @deal = Deal.create!(name: "RFQ machining", pipeline: pipelines(:sales),
                         contact: contacts(:asha), organisation: organisations(:dpg), owner: users(:admin))
    @maker = users(:sales)
    @checker = users(:supervisor)
  end

  def deliverable(**attrs)
    Deliverable.create!({ deal: @deal, title: "Feasibility report",
                          scope_items: [ { "description" => "Machine 20 brackets", "quantity" => 20, "unit" => "pcs" } ] }.merge(attrs))
  end

  test "submit_for_review moves draft to in_review and records the maker" do
    d = deliverable
    Deliverables.submit_for_review!(d, by: @maker)
    assert d.status_in_review?
    assert_equal @maker, d.submitted_by
  end

  test "submit_for_review refuses a deliverable with no scope" do
    d = deliverable(scope_items: [])
    error = assert_raises(Deliverable::Error) { Deliverables.submit_for_review!(d, by: @maker) }
    assert_match(/scope entry/, error.message)
  end

  test "approve requires a distinct human — the maker cannot approve their own" do
    d = deliverable
    Deliverables.submit_for_review!(d, by: @maker)
    error = assert_raises(Deliverable::Error) { Deliverables.approve!(d, by: @maker, reason: "looks fine") }
    assert_match(/maker cannot approve/, error.message)
  end

  test "approve requires a reasoned order" do
    d = deliverable
    Deliverables.submit_for_review!(d, by: @maker)
    error = assert_raises(Deliverable::Error) { Deliverables.approve!(d, by: @checker, reason: "  ") }
    assert_match(/reasoned order/, error.message)
  end

  test "a distinct checker approves with a reason" do
    d = deliverable
    Deliverables.submit_for_review!(d, by: @maker)
    Deliverables.approve!(d, by: @checker, reason: "Scope matches the studies and the customer RFQ.")
    assert d.status_approved?
    assert_equal @checker, d.approved_by
    assert_equal "Scope matches the studies and the customer RFQ.", d.approval_reason
  end

  test "issue freezes an approved deliverable and stamps issued_at" do
    d = deliverable
    Deliverables.submit_for_review!(d, by: @maker)
    Deliverables.approve!(d, by: @checker, reason: "Approved.")
    Deliverables.issue!(d, by: @checker)
    assert d.status_issued?
    assert d.issued_at.present?
    assert_raises(ActiveRecord::RecordInvalid) { d.update!(title: "Changed after issue") }
  end

  test "cannot skip states — issuing a draft is refused" do
    d = deliverable
    error = assert_raises(Deliverable::Error) { Deliverables.issue!(d, by: @checker) }
    assert_match(/approved deliverable/, error.message)
  end

  test "return_to_draft sends it back and clears the maker" do
    d = deliverable
    Deliverables.submit_for_review!(d, by: @maker)
    Deliverables.return_to_draft!(d, by: @checker)
    assert d.status_draft?
    assert_nil d.submitted_by
  end

  test "human_status renders the localized label" do
    assert_equal "Draft", deliverable.human_status
  end
end
