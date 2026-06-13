require "test_helper"

# The safety net: prove tenant scoping actually isolates data. A regression here
# is a data-confidentiality breach, not a bug — these must stay green before any
# shared-mode deploy. All fixtures live in :primary; :acme is an empty second
# tenant.
class CrossTenantIsolationTest < ActiveSupport::TestCase
  setup do
    @primary = tenants(:primary)
    @acme = tenants(:acme)
  end

  test "reads are invisible across tenants" do
    primary_case = cases(:pension_case)

    ActsAsTenant.with_tenant(@acme) do
      assert_empty Case.all, "acme must not see primary's cases"
      assert_nil Case.find_by(id: primary_case.id)
      assert_raises(ActiveRecord::RecordNotFound) { Case.find(primary_case.id) }
    end

    ActsAsTenant.with_tenant(@primary) do
      assert Case.exists?(primary_case.id), "primary sees its own case"
    end
  end

  test "creates auto-assign the current tenant and it is immutable" do
    contact = ActsAsTenant.with_tenant(@acme) do
      Contact.create!(name: "Acme Person", email: "person@acme.test")
    end
    assert_equal @acme, contact.tenant

    # Tenant is immutable once set.
    assert_raises(ActsAsTenant::Errors::TenantIsImmutable) do
      contact.update!(tenant: @primary)
    end
  end

  test "external_id is unique per tenant, not globally" do
    # :primary already has contact ravi with external_id CIF447192.
    ActsAsTenant.with_tenant(@acme) do
      assert Contact.new(name: "Acme Dup", external_id: "CIF447192").valid?,
             "another tenant may reuse the same external_id"
    end
    ActsAsTenant.with_tenant(@primary) do
      refute Contact.new(name: "Primary Dup", external_id: "CIF447192").valid?,
             "external_id must stay unique WITHIN a tenant"
    end
  end

  test "user email is unique per tenant, not globally" do
    ActsAsTenant.with_tenant(@acme) do
      assert User.new(name: "Acme Admin", email_address: "admin@example.com",
                      password: "password1234", role: :client_admin).valid?
    end
    ActsAsTenant.with_tenant(@primary) do
      refute User.new(name: "Primary Dup", email_address: "admin@example.com",
                      password: "password1234", role: :client_admin).valid?
    end
  end

  test "case tracking_id is unique per tenant, not globally" do
    taken = cases(:pension_case).tracking_id
    ActsAsTenant.with_tenant(@acme) do
      c = Case.new(subject: "X", tracking_id: taken, channel: :web_portal,
                   priority: :normal, contact: Contact.create!(name: "C", email: "c@acme.test"))
      c.valid?
      assert_empty c.errors[:tracking_id], "another tenant may reuse a tracking_id"
    end
  end

  test "without_tenant sees across tenants (the super_admin path)" do
    ActsAsTenant.with_tenant(@acme) { Contact.create!(name: "Acme", email: "a@acme.test") }
    primary_contacts = ActsAsTenant.with_tenant(@primary) { Contact.count }

    total = ActsAsTenant.without_tenant { Contact.count }
    assert_operator total, :>, primary_contacts, "without_tenant spans all tenants"
  end

  test "the audit chain stays one continuous chain across tenants" do
    ActsAsTenant.with_tenant(@primary) { Contact.create!(name: "P", email: "p@primary.test") }
    ActsAsTenant.with_tenant(@acme) { Contact.create!(name: "A", email: "a2@acme.test") }
    assert AuditEntry.verify_chain[:ok], "mixed-tenant audit entries verify as one chain"
  end
end
