require "test_helper"

class TenantReferentialIntegrityTest < ActiveSupport::TestCase
  def acme_user
    @acme_user ||= ActsAsTenant.with_tenant(tenants(:acme)) do
      User.create!(name: "Foreign user", email_address: "foreign-integrity@acme.test",
                   password: "password1234", role: :customer_service)
    end
  end

  test "derived guards cover a previously undeclared optional association" do
    kase = cases(:pension_case)
    refute kase.update(assignee_id: acme_user.id)
    assert kase.errors.of_kind?(:assignee, :cross_tenant)
  end

  test "derived guards cover CRM relationships without model-specific declarations" do
    foreign_organisation = ActsAsTenant.with_tenant(tenants(:acme)) do
      Organisation.create!(name: "Foreign organisation")
    end
    contact = contacts(:asha)

    refute contact.update(organisation_id: foreign_organisation.id)
    assert contact.errors.of_kind?(:organisation, :cross_tenant)
  end

  test "a join record without tenant_id cannot connect owners from two tenants" do
    membership = QueueMembership.new(queue: queues(:pensions), user_id: acme_user.id)
    refute membership.valid?
    assert membership.errors.of_kind?(:user, :cross_tenant)
  end
end
