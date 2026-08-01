require "test_helper"

class OrganisationHierarchyFlowTest < ActionDispatch::IntegrationTest
  test "an org can be created under a parent; a loop is rejected" do
    sign_in_as users(:client_admin)
    parent = Organisation.create!(name: "Parent Co", kind: "company")

    assert_difference "Organisation.count", 1 do
      post organisations_path, params: { organisation: { name: "Sub Co", kind: "branch", parent_id: parent.id } }
    end
    sub = Organisation.find_by!(name: "Sub Co")
    assert_equal parent, sub.parent

    # Making the parent a child of its own sub-account would loop → rejected.
    patch organisation_path(parent), params: { organisation: { parent_id: sub.id } }
    assert_response :unprocessable_entity
    assert_nil parent.reload.parent_id
  end
end
