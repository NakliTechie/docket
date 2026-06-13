require "test_helper"

class SoftDeleteTest < ActiveSupport::TestCase
  test "destroy hides the record but keeps the row" do
    org = organisations(:dpg)
    org.contacts.update_all(organisation_id: nil)
    assert org.destroy
    refute Organisation.exists?(org.id)
    assert Organisation.with_deleted.exists?(org.id)
    assert Organisation.only_deleted.exists?(org.id)
  end

  test "soft delete is audited as a delete action" do
    org = organisations(:branch)
    org.contacts.update_all(organisation_id: nil)
    org.destroy
    assert_equal "organisation.delete", AuditEntry.where(auditable: org).order(:id).last.action
  end

  test "contacts with cases cannot be deleted" do
    contact = contacts(:asha)
    refute contact.destroy
    assert contact.errors[:base].any?
    assert Contact.exists?(contact.id)
  end

  test "cases keep rendering soft-deleted associations" do
    kase = cases(:pension_case)
    queue = kase.queue
    queue.destroy
    assert_equal queue, kase.reload.queue
    refute CaseQueue.exists?(queue.id)
  end

  test "soft-deleted users cannot resume sessions" do
    user = users(:agent_b)
    user.destroy
    assert_nil User.find_by(id: user.id)
  end

  test "restore! brings a record back" do
    org = organisations(:branch)
    org.contacts.update_all(organisation_id: nil)
    org.destroy
    org.restore!
    assert Organisation.exists?(org.id)
  end

  # --- W1 invariant sweep -------------------------------------------------

  test "a soft-deleted user's email can be re-provisioned (M1)" do
    user = User.create!(name: "Temp", email_address: "reuse@example.com", password: "password", role: :customer_service)
    user.destroy
    assert_nothing_raised do
      User.create!(name: "Temp Again", email_address: "reuse@example.com", password: "password", role: :customer_service)
    end
  end

  test "an api token still resolves a soft-deleted owner (M2)" do
    user = users(:agent_b)
    token = ApiToken.create!(user: user, name: "tooling")
    user.destroy
    assert_equal user, token.reload.user
  end

  test "soft-deleting an SLA policy preserves its targets (M3)" do
    policy = SlaPolicy.create!(name: "Tmp SLA")
    target = policy.sla_targets.create!(priority: :high, first_response_minutes: 60, resolution_minutes: 240)
    policy.destroy
    assert SlaTarget.exists?(target.id), "soft-delete must not hard-delete child targets"
  end

  test "soft-deleting a queue preserves its memberships (M3)" do
    queue = CaseQueue.create!(name: "Tmp Queue", slug: "tmp-queue")
    membership = queue.queue_memberships.create!(user: users(:agent_a))
    queue.destroy
    assert QueueMembership.exists?(membership.id), "soft-delete must not hard-delete memberships"
  end

  test "audit entries still resolve a soft-deleted actor (M4)" do
    actor = users(:agent_a)
    entry = nil
    Current.set(actor: actor) do
      entry = AuditEntry.append!(action: "test.event", auditable: contacts(:asha))
    end
    actor.destroy
    assert_equal actor, entry.reload.actor
  end
end
