require "test_helper"

module Api
  class CrmDepthApiTest < ActionDispatch::IntegrationTest
    setup { @token = api_token_for(users(:admin)) }

    test "catalog line items and competitors round trip through the API" do
      post "/api/v1/products", params: { product: {
        name: "API plan", sku: "API-PLAN", default_unit_price: "99.50", currency: "INR"
      } }, headers: auth_header(@token), as: :json
      assert_response :created
      product_id = response.parsed_body.dig("data", "id")

      deal = Deal.create!(name: "API priced", pipeline: pipelines(:sales), currency: "INR")
      post "/api/v1/deals/#{deal.id}/line_items", params: { deal_line_item: {
        product_id: product_id, quantity: "3"
      } }, headers: auth_header(@token), as: :json
      assert_response :created
      assert_equal 29_850, response.parsed_body.dig("data", "total_cents")
      assert_equal 29_850, deal.reload.value_cents

      delete "/api/v1/products/#{product_id}", headers: auth_header(@token)
      assert_response :unprocessable_entity

      post "/api/v1/competitors", params: { competitor: { name: "API Rival" } },
           headers: auth_header(@token), as: :json
      competitor_id = response.parsed_body.dig("data", "id")
      post "/api/v1/deals/#{deal.id}/competitor_links", params: { deal_competitor: {
        competitor_id: competitor_id, disposition: "active"
      } }, headers: auth_header(@token), as: :json
      assert_response :created
      assert_equal "API Rival", response.parsed_body.dig("data", "competitor_name")

      delete "/api/v1/competitors/#{competitor_id}", headers: auth_header(@token)
      assert_response :unprocessable_entity

      get "/api/v1/deals/#{deal.id}", headers: auth_header(@token)
      assert_equal 29_850, response.parsed_body.dig("data", "line_items_total_cents")
      assert_equal "API Rival", response.parsed_body.dig("data", "competitors", 0, "competitor_name")
    end

    test "lead capture configuration and reviewed merge have API parity" do
      post "/api/v1/lead_capture_forms", params: { lead_capture_form: {
        name: "API form", slug: "api-form", active: true,
        field_mapping: { full_name: "name", email_address: "email" }
      } }, headers: auth_header(@token), as: :json
      assert_response :created
      assert_equal "email", response.parsed_body.dig("data", "field_mapping", "email_address")

      target = Lead.create!(name: "API target", email: "api-merge@example.com")
      source = Lead.create!(name: "API source", email: "api-merge@example.com")
      post "/api/v1/leads/#{target.id}/merge", params: { source_lead_id: source.id },
           headers: auth_header(@token), as: :json
      assert_response :success
      assert_equal target, source.reload.merged_into
      assert_includes response.parsed_body.dig("data", "merged_lead_ids"), source.id
    end

    test "sales API reports competitor losses by currency" do
      competitor = Competitor.create!(name: "API loss rival")
      deal = Deal.create!(name: "API loss", pipeline: pipelines(:sales),
                          pipeline_stage: pipeline_stages(:sales_lost), value: 120, currency: "USD")
      DealCompetitor.create!(deal: deal, competitor: competitor, disposition: :lost_to)

      get "/api/v1/reports/sales", headers: auth_header(@token)

      assert_response :success
      row = response.parsed_body.dig("data", "competitor_losses")
                    .find { |candidate| candidate["competitor"] == competitor.name }
      assert_equal "USD", row["currency"]
      assert_equal 12_000, row["value_cents"]
    end
  end
end
