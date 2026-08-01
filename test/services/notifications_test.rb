require "test_helper"

class NotificationsEventTest < ActiveSupport::TestCase
  test "deduplicates repeated risk and reopens the same notification on breach escalation" do
    kase = cases(:assigned_case)
    recipient = users(:agent_a)
    attributes = {
      recipient: recipient, notifiable: kase, dedupe_key: "case:#{kase.id}:sla:resolution",
      title: "At risk", body: "Risk", metadata: { reference: kase.tracking_id, clock: "resolution" },
      repeat: false
    }

    first = Notifications::Publish.call(**attributes, kind: :sla_risk, severity: :warning)
    first.mark_read!
    repeated = Notifications::Publish.call(**attributes, kind: :sla_risk, severity: :warning)

    assert_equal first, repeated
    assert_equal 1, repeated.occurrences
    assert_not repeated.unread?

    breached = Notifications::Publish.call(
      **attributes, kind: :sla_breach, severity: :critical,
      title: "Breached", body: "Breach"
    )
    assert_equal first.id, breached.id
    assert breached.unread?
    assert breached.severity_critical?
    assert breached.kind_sla_breach?
    assert_equal 2, breached.occurrences
  end

  test "case and work assignments notify the new assignee" do
    kase = cases(:pension_case)
    kase.update!(assignee: users(:agent_b))
    case_notification = users(:agent_b).notifications.find_by!(notifiable: kase)
    assert case_notification.kind_assignment?

    item = work_items(:pep_one)
    item.update!(assignee: users(:agent_b))
    work_notification = users(:agent_b).notifications.find_by!(notifiable: item)
    assert work_notification.kind_assignment?
  end

  test "mentions resolve an exact bracketed staff email and never notify the author" do
    message = cases(:pension_case).messages.create!(
      body: "Please check this @[agent.b@example.com] and @[agent.a@example.com]",
      kind: :internal_note, direction: :outbound, author: users(:agent_a)
    )

    assert users(:agent_b).notifications.where(kind: :mention, notifiable: message.case).exists?
    refute users(:agent_a).notifications.where(kind: :mention, notifiable: message.case).exists?
  end

  test "watchers receive transitions and comments but the acting watcher does not notify themself" do
    item = work_items(:pep_one)
    item.work_watches.create!(user: users(:agent_b))
    item.transition_to!(workflow_states(:pep_in_progress))

    assert users(:agent_b).notifications.where(kind: :watched_work, notifiable: item).exists?

    before = users(:agent_b).notifications.count
    item.work_comments.create!(body: "Following up", author: users(:agent_b))
    assert_equal before, users(:agent_b).notifications.count

    item.work_comments.create!(body: "Update", author: users(:admin))
    assert_equal before + 1, users(:agent_b).notifications.count
  end

  test "notification ownership cannot cross a tenant boundary" do
    notification = Notifications::Publish.call(
      recipient: users(:agent_a), kind: :assignment, notifiable: cases(:assigned_case),
      dedupe_key: "tenant-proof", title: "Assigned", body: "Primary"
    )

    ActsAsTenant.with_tenant(tenants(:acme)) do
      assert_empty Notification.where(id: notification.id)
    end
  end
end
