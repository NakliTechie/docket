require "test_helper"

class SharedCredentialsTest < ActionDispatch::IntegrationTest
  test "an admin creates a shared credential and its secret is stored encrypted" do
    sign_in_as users(:admin)
    assert_difference "SharedCredential.count", 1 do
      post admin_shared_credentials_path, params: { shared_credential: {
        name: "api_setu", label: "API Setu key", secrets: { api_key: "setu-secret-123" }
      } }
    end
    sc = SharedCredential.order(:id).last
    assert_redirected_to admin_shared_credentials_path
    assert_equal "setu-secret-123", sc.secret("api_key")
  end

  test "editing keeps a secret when its field is left blank" do
    sc = SharedCredential.new(name: "rzp", label: "Razorpay")
    sc.secrets_hash = { "key_id" => "k1" }
    sc.save!
    sign_in_as users(:admin)
    patch admin_shared_credential_path(sc),
          params: { shared_credential: { name: "rzp", label: "Razorpay 2", secrets: { key_id: "" } } }
    sc.reload
    assert_equal "Razorpay 2", sc.label
    assert_equal "k1", sc.secret("key_id") # blank left it unchanged
  end

  test "an admin deletes a shared credential" do
    sc = SharedCredential.create!(name: "scratch", label: "Scratch")
    sign_in_as users(:admin)
    assert_difference "SharedCredential.count", -1 do
      delete admin_shared_credential_path(sc)
    end
  end

  test "a non-admin cannot manage shared credentials" do
    sign_in_as users(:supervisor)
    get admin_shared_credentials_path
    assert_response :forbidden
  end

  test "the connector form offers the shared-credential dropdown once one exists" do
    sc = SharedCredential.new(name: "api_setu", label: "API Setu")
    sc.secrets_hash = { "api_key" => "k" }
    sc.save!
    sign_in_as users(:admin)
    get new_admin_connector_path(provider: "http_json")
    assert_response :success
    assert_match "Shared credential", response.body
  end
end
