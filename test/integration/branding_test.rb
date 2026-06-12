require "test_helper"

# The product reads private-first: a neutral default brand + neutral
# vocabulary, with the brand configurable per deploy (gov is a special case).
class BrandingTest < ActionDispatch::IntegrationTest
  test "the brand defaults to the product name in the staff header" do
    sign_in_as users(:admin)
    get root_path
    assert_response :success
    assert_match "Docket", response.body
  end

  test "an admin sets a custom brand and it shows in the header and the portal" do
    Setting.set("brand_name", "Acme Support")
    sign_in_as users(:admin)
    get admin_settings_path
    assert_match "Acme Support", response.body

    reset! # anonymous
    get "/portal"
    assert_response :success
    assert_match "Acme Support", response.body
  end

  test "settings accepts the brand_name" do
    sign_in_as users(:admin)
    patch admin_settings_path, params: { brand_name: "Globex" }
    assert_equal "Globex", Setting.get("brand_name")
  end

  test "the customer portal reads private-first — no grievance language" do
    get "/portal"
    assert_response :success
    assert_no_match(/grievance/i, response.body)
    assert_match "Submit a request", response.body
  end
end
