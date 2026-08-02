require "test_helper"

class EntitlementsTest < ActionDispatch::IntegrationTest
  test "configuration managers can manage service contracts" do
    sign_in_as users(:client_admin)

    get entitlements_path
    assert_response :success

    assert_difference "Entitlement.count", 1 do
      post entitlements_path, params: { entitlement: {
        name: "Northwind premium", organisation_id: organisations(:dpg).id,
        contact_id: "", sla_policy_id: sla_policies(:standard).id,
        starts_at: "2026-08-01T09:00", ends_at: "2027-08-01T09:00"
      } }
    end
    entitlement = Entitlement.find_by!(name: "Northwind premium")
    assert_redirected_to entitlements_path
    assert_equal organisations(:dpg), entitlement.organisation

    patch entitlement_path(entitlement), params: {
      entitlement: { name: "Northwind priority", organisation_id: "",
                     contact_id: contacts(:asha).id }
    }
    assert_redirected_to entitlements_path
    assert_equal contacts(:asha), entitlement.reload.contact

    delete entitlement_path(entitlement)
    assert_redirected_to entitlements_path
    assert entitlement.reload.deleted?
  end

  test "customer-service users can inspect but cannot change contracts" do
    sign_in_as users(:customer_service)

    get entitlements_path
    assert_response :success
    get new_entitlement_path
    assert_response :forbidden
    assert_no_difference "Entitlement.count" do
      post entitlements_path, params: { entitlement: {
        name: "Forbidden", contact_id: contacts(:asha).id,
        sla_policy_id: sla_policies(:standard).id, starts_at: Time.current
      } }
    end
  end
end
