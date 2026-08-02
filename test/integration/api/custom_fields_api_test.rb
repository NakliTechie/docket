require "test_helper"

module Api
  class CustomFieldsApiTest < ActionDispatch::IntegrationTest
    setup do
      @token = api_token_for(users(:admin))
      @headers = auth_header(@token)
    end

    test "definition management and resource values have API parity" do
      post "/api/v1/custom_fields", params: { custom_field: {
        resource_type: "cases", key: "region", label: "Region", field_type: "single_select",
        options: %w[North South], required: false, reportable: true
      } }, headers: @headers, as: :json
      assert_response :created
      definition = response.parsed_body.fetch("data")

      patch "/api/v1/custom_fields/#{definition.fetch('id')}", params: { custom_field: {
        key: "cannot_change", label: "Customer region", active: true
      } }, headers: @headers, as: :json
      assert_response :success
      assert_equal "region", response.parsed_body.dig("data", "key")

      patch "/api/v1/cases/#{cases(:pension_case).id}", params: { case: {
        custom_fields: { region: "North" }
      } }, headers: @headers, as: :json
      assert_response :success
      assert_equal "North", response.parsed_body.dig("data", "custom_fields", "region")

      get "/api/v1/custom_fields", params: { resource_type: "cases" }, headers: @headers
      assert_response :success
      assert_equal [ "region" ], response.parsed_body.fetch("data").map { |field| field.fetch("key") }
    end

    test "custom-field report uses the resource read scope" do
      CustomFieldDefinition.create!(resource_type: "work_items", key: "environment",
                                    label: "Environment", field_type: :short_text, reportable: true)
      item = work_items(:pep_one)
      item.assign_custom_fields(environment: "Production")
      item.save!

      token = service_token_for(%w[work:read])
      get "/api/v1/reports/custom_fields",
          params: { resource_type: "work_items", field: "environment" },
          headers: auth_header(token)
      assert_response :success
      assert_equal "Production", response.parsed_body.dig("data", "rows", 0, "label")
    end

    test "CRM definitions values and reports have API parity" do
      post "/api/v1/custom_fields", params: { custom_field: {
        resource_type: "leads", key: "account_tier", label: "Account tier",
        field_type: "single_select", options: %w[Gold Silver], reportable: true
      } }, headers: @headers, as: :json
      assert_response :created

      post "/api/v1/leads", params: { lead: {
        name: "API governed lead", email: "api-governed-lead@example.test",
        custom_fields: { account_tier: "Gold" }
      } }, headers: @headers, as: :json
      assert_response :created
      assert_equal "Gold", response.parsed_body.dig("data", "custom_fields", "account_tier")

      get "/api/v1/reports/custom_fields",
          params: { resource_type: "leads", field: "account_tier" }, headers: @headers
      assert_response :success
      assert_equal "Gold", response.parsed_body.dig("data", "rows", 0, "label")
    end

    test "service-account config scopes separate definition reads from writes" do
      CustomFieldDefinition.create!(resource_type: "deals", key: "route", label: "Route",
                                    field_type: :short_text)
      read_headers = auth_header(service_token_for(%w[config:read crm:read]))
      get "/api/v1/custom_fields", params: { resource_type: "deals" }, headers: read_headers
      assert_response :success
      assert_equal [ "route" ], response.parsed_body.fetch("data").map { |field| field.fetch("key") }

      post "/api/v1/custom_fields", params: { custom_field: {
        resource_type: "deals", key: "blocked", label: "Blocked", field_type: "short_text"
      } }, headers: read_headers, as: :json
      assert_response :forbidden

      write_headers = auth_header(service_token_for(%w[config:write]))
      post "/api/v1/custom_fields", params: { custom_field: {
        resource_type: "deals", key: "approved", label: "Approved", field_type: "short_text"
      } }, headers: write_headers, as: :json
      assert_response :created
    end
  end
end
