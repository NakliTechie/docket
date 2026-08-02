require "test_helper"

class EntitlementTest < ActiveSupport::TestCase
  setup do
    @contact = contacts(:asha)
    @organisation = organisations(:dpg)
    @default_policy = sla_policies(:standard)
    @organisation_policy = SlaPolicy.create!(name: "Organisation support")
    @contact_policy = SlaPolicy.create!(name: "Contact support")
  end

  test "contact entitlement takes precedence over organisation and tenant defaults" do
    Setting.set("default_sla_policy_id", @default_policy.id)
    create_entitlement(name: "Organisation contract", organisation: @organisation,
                       sla_policy: @organisation_policy)
    create_entitlement(name: "Contact contract", contact: @contact,
                       sla_policy: @contact_policy)

    kase = Case.create!(subject: "Covered request", contact: @contact)

    assert_equal @contact_policy, kase.sla_policy
  ensure
    Setting.unset("default_sla_policy_id")
  end

  test "organisation entitlement precedes the tenant default" do
    Setting.set("default_sla_policy_id", @default_policy.id)
    create_entitlement(name: "Organisation contract", organisation: @organisation,
                       sla_policy: @organisation_policy)

    kase = Case.create!(subject: "Covered request", contact: @contact)

    assert_equal @organisation_policy, kase.sla_policy
  ensure
    Setting.unset("default_sla_policy_id")
  end

  test "expired and retired-policy entitlements fall back to the tenant default" do
    Setting.set("default_sla_policy_id", @default_policy.id)
    create_entitlement(name: "Expired contract", contact: @contact,
                       sla_policy: @contact_policy, starts_at: 2.months.ago, ends_at: 1.month.ago)
    current = create_entitlement(name: "Retired contract", organisation: @organisation,
                                 sla_policy: @organisation_policy)
    current.sla_policy.destroy

    kase = Case.create!(subject: "Default request", contact: @contact)

    assert_equal @default_policy, kase.sla_policy
  ensure
    Setting.unset("default_sla_policy_id")
  end

  test "explicit case policy keeps precedence" do
    create_entitlement(name: "Contact contract", contact: @contact,
                       sla_policy: @contact_policy)

    kase = Case.create!(subject: "Explicit request", contact: @contact,
                        sla_policy: @default_policy)

    assert_equal @default_policy, kase.sla_policy
  end

  test "requires exactly one holder and an ordered coverage window" do
    entitlement = Entitlement.new(name: "Invalid", sla_policy: @default_policy,
                                  starts_at: 1.day.from_now, ends_at: Time.current)

    refute entitlement.valid?
    assert entitlement.errors[:base].any?
    assert entitlement.errors[:ends_at].any?

    entitlement.organisation = @organisation
    entitlement.contact = @contact
    refute entitlement.valid?
    assert entitlement.errors[:base].any?
  end

  private

  def create_entitlement(name:, sla_policy:, organisation: nil, contact: nil,
                         starts_at: 1.day.ago, ends_at: nil)
    Entitlement.create!(name: name, organisation: organisation, contact: contact,
                        sla_policy: sla_policy, starts_at: starts_at, ends_at: ends_at)
  end
end
