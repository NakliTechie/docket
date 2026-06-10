require "test_helper"

module Api
  class OpenapiTest < ActionDispatch::IntegrationTest
    test "spec is served publicly and is valid json" do
      get "/api/v1/openapi.json"
      assert_response :success
      body = response.parsed_body
      assert_equal "3.1.0", body["openapi"]
      assert body["paths"].any?
    end

    # The agent face is non-negotiable (handoff §12): every /api/v1
    # route must be documented.
    test "every api route is documented in the spec" do
      get "/api/v1/openapi.json"
      documented = response.parsed_body["paths"].keys

      app_routes = Rails.application.routes.routes.filter_map do |route|
        path = route.path.spec.to_s.sub("(.:format)", "")
        next unless path.start_with?("/api/v1/")
        path.delete_prefix("/api/v1").gsub(/:(\w+)/) { "{#{Regexp.last_match(1)}}" }
      end.uniq

      missing = app_routes - documented
      assert_empty missing, "Undocumented API routes: #{missing.inspect}"
    end
  end
end
