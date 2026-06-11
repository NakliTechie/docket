require "test_helper"

module Api
  class ResourcesApiTest < ActionDispatch::IntegrationTest
    setup do
      @admin_token = api_token_for(users(:admin))
    end

    test "external_id cannot be rewritten through the contacts api (L)" do
      contact = contacts(:ravi)
      patch "/api/v1/contacts/#{contact.id}",
            params: { contact: { name: "Renamed", external_id: "HIJACK" } },
            headers: auth_header(@admin_token), as: :json
      assert_response :success
      contact.reload
      assert_equal "Renamed", contact.name
      assert_equal "CIF447192", contact.external_id
    end

    test "contacts crud with ext addressing" do
      post "/api/v1/contacts", params: { contact: { name: "Via API", email: "viaapi@example.com", external_id: "CIFAPI1" } },
           headers: auth_header(@admin_token), as: :json
      assert_response :created

      get "/api/v1/contacts/ext:CIFAPI1", headers: auth_header(@admin_token)
      assert_response :success
      assert_equal "Via API", response.parsed_body["data"]["name"]

      get "/api/v1/contacts", params: { q: "viaapi" }, headers: auth_header(@admin_token)
      assert_equal 1, response.parsed_body["data"].size
    end

    test "organisations queues categories sla_policies macros reference_docs crud" do
      resources = {
        "organisations" => { organisation: { name: "API Org", kind: "department" } },
        "queues" => { queue: { name: "API Queue" } },
        "categories" => { category: { name: "API Category" } },
        "sla_policies" => { sla_policy: { name: "API SLA" } },
        "macros" => { macro: { name: "API Macro", body: "Hello {{contact_name}}" } },
        "reference_docs" => { reference_doc: { title: "API Doc", body: "Grounding text." } }
      }
      resources.each do |path, payload|
        post "/api/v1/#{path}", params: payload, headers: auth_header(@admin_token), as: :json
        assert_response :created, "create #{path}: #{response.body}"
        id = response.parsed_body["data"]["id"]

        get "/api/v1/#{path}", headers: auth_header(@admin_token)
        assert_response :success

        get "/api/v1/#{path}/#{id}", headers: auth_header(@admin_token)
        assert_response :success

        delete "/api/v1/#{path}/#{id}", headers: auth_header(@admin_token)
        assert_response :no_content, "delete #{path}"
      end
    end

    test "queues addressable by slug" do
      get "/api/v1/queues/#{queues(:pensions).slug}", headers: auth_header(@admin_token)
      assert_response :success
      assert_equal queues(:pensions).id, response.parsed_body["data"]["id"]
    end

    test "config scope gates config resources for service accounts" do
      read_token = service_token_for(%w[config:read])
      get "/api/v1/queues", headers: auth_header(read_token)
      assert_response :success
      post "/api/v1/queues", params: { queue: { name: "Denied" } },
           headers: auth_header(read_token), as: :json
      assert_response :forbidden

      write_token = service_token_for(%w[config:read config:write])
      post "/api/v1/queues", params: { queue: { name: "Allowed" } },
           headers: auth_header(write_token), as: :json
      assert_response :created
    end

    test "agents cannot manage config resources via api" do
      token = api_token_for(users(:agent_a))
      post "/api/v1/queues", params: { queue: { name: "Agent Queue" } },
           headers: auth_header(token), as: :json
      assert_response :forbidden
    end

    test "category auto-resolve toggle is human-admin only" do
      category = categories(:pension_delay)
      post "/api/v1/categories/#{category.id}/toggle_auto_resolve", headers: auth_header(@admin_token)
      assert_response :success
      assert category.reload.ai_auto_resolve

      sa_token = service_token_for(%w[config:write])
      post "/api/v1/categories/#{category.id}/toggle_auto_resolve", headers: auth_header(sa_token)
      assert_response :forbidden

      agent_token = api_token_for(users(:agent_a))
      post "/api/v1/categories/#{category.id}/toggle_auto_resolve", headers: auth_header(agent_token)
      assert_response :forbidden
    end
  end
end
