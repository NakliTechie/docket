require "test_helper"

# Signed-in customer (portal) case filing. Pins H7 (a rejected attachment
# must roll the case back, not 500 with an orphan) and M10 (filed cases
# get the default queue like every other intake surface).
class PortalMyCasesTest < ActionDispatch::IntegrationTest
  setup do
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:customer_oidc] = OmniAuth::AuthHash.new(
      provider: "customer_oidc", uid: "CIF900100",
      info: { email: "mycases@example.com", name: "My Cases Customer" },
      extra: { raw_info: {} }
    )
    get "/auth/customer_oidc/callback" # establishes the customer session
  end

  teardown do
    OmniAuth.config.test_mode = false
    OmniAuth.config.mock_auth.delete(:customer_oidc)
  end

  test "a rejected attachment rolls the case back instead of 500ing with an orphan (H7)" do
    too_many = Array.new(6) { |i| text_upload("f#{i}") }

    assert_no_difference -> { Case.count } do
      post portal_my_cases_path, params: {
        case: { subject: "Has bad files", description: "Body text", files: too_many }
      }
    end
    assert_response :unprocessable_entity
  end

  test "a valid filed case is created with the default queue (M10)" do
    Setting.set("default_queue_id", queues(:pensions).id)

    assert_difference -> { Case.count }, 1 do
      post portal_my_cases_path, params: {
        case: { subject: "Routine", description: "Please help with my pension." }
      }
    end
    kase = Case.order(:id).last
    assert_equal queues(:pensions), kase.queue
  end

  test "an out-of-range page number lands on the last page, not a 500 (L)" do
    get portal_my_cases_path(page: 9_999)
    assert_response :success
  end

  private

  def text_upload(name)
    file = Tempfile.new([ name, ".txt" ])
    file.write("hello from #{name}")
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "text/plain", original_filename: "#{name}.txt")
  end
end
