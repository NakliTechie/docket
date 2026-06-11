require "test_helper"

class CaseTest < ActiveSupport::TestCase
  test "generates citizen-friendly unguessable tracking id on create" do
    kase = Case.create!(subject: "Test", contact: contacts(:asha))
    assert_match(/\ADKT-[A-Z2-9]{4}-[A-Z2-9]{4}\z/, kase.tracking_id)
    refute_match(/[01OILU]/, kase.tracking_id.delete_prefix("DKT-"))
  end

  test "tracking ids are unique" do
    ids = 50.times.map { Case.generate_tracking_id }
    assert_equal ids.uniq.size, ids.size
  end

  test "applies default sla policy from settings on create" do
    Setting.set("default_sla_policy_id", sla_policies(:standard).id)
    kase = Case.create!(subject: "Test", contact: contacts(:asha))
    assert_equal sla_policies(:standard), kase.sla_policy
    assert_in_delta 120.minutes, kase.first_response_due_at - kase.created_at, 5
    assert_in_delta 2880.minutes, kase.resolution_due_at - kase.created_at, 5
  ensure
    Setting.unset("default_sla_policy_id")
  end

  test "recomputes sla due dates when priority changes" do
    kase = Case.create!(subject: "Test", contact: contacts(:asha),
                        sla_policy: sla_policies(:standard), priority: :normal)
    original_due = kase.first_response_due_at
    kase.update!(priority: :high)
    assert kase.first_response_due_at < original_due
    assert_in_delta 30.minutes, kase.first_response_due_at - kase.created_at, 5
  end

  test "walks the locked happy path" do
    kase = cases(:pension_case)
    %w[triaged in_progress waiting_on_citizen in_progress resolved closed].each do |status|
      kase.transition_to!(status)
      assert_equal status, kase.reload.status
    end
  end

  test "rejects illegal transitions" do
    assert_raises(Case::InvalidTransition) { cases(:pension_case).transition_to!(:closed) }
    assert_raises(Case::InvalidTransition) { cases(:pension_case).transition_to!(:reopened) }
    assert_raises(Case::InvalidTransition) { cases(:resolved_case).transition_to!(:in_progress) }
  end

  test "rejects status mutation outside the state machine" do
    kase = cases(:pension_case)
    assert_raises(ActiveRecord::RecordInvalid) { kase.update!(status: :closed) }
    assert_equal "new", kase.reload.status
  end

  test "stamps lifecycle timestamps on transition" do
    kase = cases(:assigned_case)
    kase.transition_to!(:resolved)
    assert kase.resolved_at.present?
    kase.transition_to!(:closed)
    assert kase.closed_at.present?
    kase.transition_to!(:reopened)
    assert kase.reopened_at.present?
    assert_equal 1, kase.reopen_count
    assert_nil kase.resolved_at
    assert_nil kase.closed_at
  end

  test "record_first_response! only stamps once" do
    kase = cases(:pension_case)
    kase.record_first_response!(at: Time.current)
    first = kase.first_responded_at
    kase.record_first_response!(at: 1.hour.from_now)
    assert_equal first, kase.reload.first_responded_at
  end

  test "overdue scopes find breaching cases" do
    kase = cases(:pension_case)
    kase.update_columns(first_response_due_at: 1.hour.ago, resolution_due_at: 1.hour.ago)
    assert_includes Case.overdue_first_response, kase
    assert_includes Case.overdue_resolution, kase
    kase.update_columns(first_response_breached: true, resolution_breached: true)
    refute_includes Case.overdue_first_response, kase
    refute_includes Case.overdue_resolution, kase
  end

  test "search matches subject and tracking id case-insensitively" do
    assert_includes Case.search("PENSION"), cases(:pension_case)
    assert_includes Case.search("dkt-test-2345"), cases(:pension_case)
    refute_includes Case.search("zzzznothing"), cases(:pension_case)
  end

  test "reopening resets the resolution clock so a stale due date isn't an instant breach (M17)" do
    kase = Case.create!(subject: "Reopen me", contact: contacts(:asha), queue: queues(:pensions),
                        sla_policy: sla_policies(:standard), priority: :normal, channel: :web_portal)
    kase.transition_to!(:in_progress)
    kase.transition_to!(:resolved)
    # The original resolution window is long gone.
    kase.update_columns(resolution_due_at: 3.days.ago)

    kase.transition_to!(:reopened)
    assert kase.resolution_due_at > Time.current, "reopen should set a fresh future resolution due date"
    refute_includes Case.overdue_resolution, kase
  end
end
