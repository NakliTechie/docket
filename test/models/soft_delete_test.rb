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
end
