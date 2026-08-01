require "test_helper"

class Customer360Test < ActiveSupport::TestCase
  setup { @contact = contacts(:asha) }

  def full_360
    Customer360.new(subject: @contact, case_scope: Case.all, deal_scope: Deal.all, work_scope: WorkItem.all).call
  end

  test "the timeline interleaves cases, communications and resolutions newest-first" do
    kase = Case.create!(subject: "Login broken", contact: @contact)
    kase.messages.create!(kind: :public_reply, direction: :inbound, body: "I can't log in", author: @contact)
    kase.transition_to!(:in_progress)
    kase.transition_to!(:resolved)
    Deal.create!(name: "Renewal", pipeline: pipelines(:sales), contact: @contact)

    timeline = full_360.timeline
    kinds = timeline.map(&:kind)
    assert_includes kinds, :case_opened
    assert_includes kinds, :message
    assert_includes kinds, :case_resolved
    assert_includes kinds, :deal_opened

    ats = timeline.map(&:at)
    assert_equal ats.sort.reverse, ats, "timeline must be newest-first"
  end

  test "a won deal emits both open and win events" do
    deal = Deal.create!(name: "Big", pipeline: pipelines(:sales), contact: @contact)
    deal.update!(pipeline_stage: pipeline_stages(:sales_won))
    kinds = full_360.timeline.select { |event| event.record == deal }.map(&:kind)
    assert_equal %i[deal_opened deal_won].sort, kinds.sort
  end

  test "a module whose scope is none contributes no events" do
    Case.create!(subject: "hidden", contact: @contact)
    result = Customer360.new(subject: @contact, case_scope: Case.none,
                             deal_scope: Deal.none, work_scope: WorkItem.none).call
    assert_empty result.timeline
  end

  test "internal AI agent_turn messages stay out of the customer timeline" do
    contact = Contact.create!(name: "Fresh Lead", email: "fresh.360@example.com")
    kase = Case.create!(subject: "AI case", contact: contact)
    kase.messages.create!(kind: :agent_turn, direction: :outbound, body: "internal reasoning",
                          author: users(:agent_a))
    isolated = Customer360.new(subject: contact, case_scope: Case.all,
                               deal_scope: Deal.all, work_scope: WorkItem.all)
    assert_empty isolated.call.timeline.select { |event| event.kind == :message },
                 "agent_turn is internal AI reasoning, not a communication"

    # Positive control: a real public reply on the same case does surface.
    kase.messages.create!(kind: :public_reply, direction: :outbound, body: "We're on it",
                          author: users(:agent_a))
    assert_equal 1, isolated.call.timeline.count { |event| event.kind == :message }
  end
end
