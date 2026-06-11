module Docket
  # Builds the OpenAPI 3.1 document served at /api/v1/openapi.json.
  # Deliberately declarative; test/integration/api/openapi_test.rb
  # asserts every /api/v1 route is documented.
  module Openapi
    module_function

    def document
      {
        openapi: "3.1.0",
        info: {
          title: "Docket API",
          version: "v1",
          description: "Sovereign case-management API. Every action the UI can perform is available here. " \
                       "Auth: per-user tokens (`Authorization: Bearer dkt_…`) carry that user's console permissions; " \
                       "service accounts exchange client credentials at /oauth/token for a scoped bearer (`dkts_…`). " \
                       "Scoped service accounts may act on behalf of a contact via `on_behalf_of` (the operator's customer ID)."
        },
        servers: [ { url: "/api/v1" } ],
        components: components,
        security: [ { bearerAuth: [] } ],
        paths: paths
      }
    end

    def components
      {
        securitySchemes: {
          bearerAuth: { type: "http", scheme: "bearer" }
        },
        schemas: {
          Case: object_schema(
            id: :integer, tracking_id: :string, subject: :string, description: :string,
            status: enum(Case.statuses.keys), priority: enum(Case.priorities.keys),
            channel: enum(Case.channels.keys), queue_id: :integer, queue_slug: :string,
            category_id: :integer, category: :string, assignee_id: :integer, contact_id: :integer,
            sla_policy_id: :integer, first_response_due_at: :datetime, resolution_due_at: :datetime,
            first_responded_at: :datetime, resolved_at: :datetime, closed_at: :datetime,
            first_response_breached: :boolean, resolution_breached: :boolean, reopen_count: :integer,
            allowed_transitions: { type: "array", items: { type: "string" } },
            created_at: :datetime, updated_at: :datetime
          ),
          Message: object_schema(
            id: :integer, case_id: :integer, kind: enum(Message.kinds.keys),
            direction: enum(Message.directions.keys), author_type: :string, author_id: :integer,
            subject: :string, body: :string, metadata: :object,
            attachments: { type: "array", items: { type: "object" } }, created_at: :datetime
          ),
          Contact: object_schema(
            id: :integer, name: :string, email: :string, phone: :string, external_id: :string,
            organisation_id: :integer, preferred_language: :string, notes: :string,
            created_at: :datetime, updated_at: :datetime
          ),
          Organisation: object_schema(id: :integer, name: :string, kind: :string, external_ref: :string,
                                      notes: :string, created_at: :datetime, updated_at: :datetime),
          Lead: object_schema(id: :integer, name: :string, email: :string, phone: :string,
                              company_name: :string, source: enum(Lead.sources.keys), status: enum(Lead.statuses.keys),
                              owner_id: :integer, contact_id: :integer, value_estimate_cents: :integer,
                              notes: :string, converted_at: :datetime, created_at: :datetime, updated_at: :datetime),
          Queue: object_schema(id: :integer, name: :string, slug: :string, description: :string,
                               member_ids: { type: "array", items: { type: "integer" } },
                               created_at: :datetime, updated_at: :datetime),
          Category: object_schema(id: :integer, name: :string, description: :string,
                                  ai_auto_resolve: :boolean, created_at: :datetime, updated_at: :datetime),
          SlaPolicy: object_schema(id: :integer, name: :string, description: :string,
                                   targets: { type: "array", items: { type: "object" } },
                                   created_at: :datetime, updated_at: :datetime),
          Macro: object_schema(id: :integer, name: :string, body: :string, created_at: :datetime, updated_at: :datetime),
          ReferenceDoc: object_schema(id: :integer, title: :string, body: :string, created_at: :datetime, updated_at: :datetime),
          User: object_schema(id: :integer, name: :string, email_address: :string,
                              role: enum(User.roles.keys), active: :boolean, locale: :string,
                              queue_ids: { type: "array", items: { type: "integer" } },
                              created_at: :datetime, updated_at: :datetime),
          AuditEntry: object_schema(id: :integer, action: :string, actor_type: :string, actor_id: :integer,
                                    auditable_type: :string, auditable_id: :integer, changeset: :object,
                                    metadata: :object, previous_sha: :string, sha: :string, created_at: :datetime),
          WebhookEndpoint: object_schema(id: :integer, name: :string, url: :string,
                                         events: { type: "array", items: enum(WebhookEndpoint::EVENTS) },
                                         active: :boolean, created_at: :datetime, updated_at: :datetime),
          WebhookDelivery: object_schema(id: :integer, webhook_endpoint_id: :integer, event: :string,
                                         status: :string, attempts: :integer, response_code: :integer,
                                         last_error: :string, delivered_at: :datetime, created_at: :datetime),
          ServiceAccount: object_schema(id: :integer, name: :string, description: :string, client_id: :string,
                                        scopes: { type: "array", items: enum(ServiceAccount::SCOPES) },
                                        active: :boolean, created_at: :datetime, updated_at: :datetime),
          ApiToken: object_schema(id: :integer, user_id: :integer, name: :string,
                                  last_used_at: :datetime, revoked_at: :datetime, created_at: :datetime),
          Error: object_schema(error: :string, detail: :string)
        }
      }
    end

    def paths
      result = {}

      result["/oauth/token"] = {
        post: op("Exchange service-account client credentials for a scoped bearer token",
                 security: [], request: {
                   grant_type: { type: "string", enum: [ "client_credentials" ] },
                   client_id: :string, client_secret: :string
                 },
                 responses: { "200" => "Access token issued", "401" => "Invalid client" })
      }
      result["/openapi.json"] = { get: op("This document", security: []) }

      crud(result, "cases", "Case",
           extra_params: %w[q status priority queue_id assignee_id contact_id contact_external_id],
           create_note: "Service accounts may pass on_behalf_of (contact external_id) plus an optional contact{} for upsert, and message_body for the initial citizen message. case[attachments]/case[files] attach to that initial message. Cases are addressable by numeric id or tracking ID.")
      result["/cases/{id}/transition"] = { post: op("Transition case status through the state machine",
        params: [ id_param ], request: { status: enum(Case.statuses.keys) },
        responses: { "200" => "Transitioned", "422" => "Illegal transition" }) }
      result["/cases/{id}/assign"] = { post: op("Assign or unassign the case",
        params: [ id_param ], request: { assignee_id: :integer }) }
      result["/cases/{case_id}/messages"] = {
        get: op("List messages on a case", params: [ case_id_param ]),
        post: op("Add a message (public_reply or internal_note). Service accounts may pass on_behalf_of to author as the contact. " \
                 "Attachments: multipart message[files][], or JSON message[attachments] = [{filename, content_type, data(base64)}] — " \
                 "same type allowlist and 10MB/5-file limits as every surface.",
                 params: [ case_id_param ], request: { message: :object })
      }
      result["/cases/{case_id}/assist/summarise"] = { post: op("AI: summarise the case thread (404 when AI is off)", params: [ case_id_param ]) }
      result["/cases/{case_id}/assist/suggest_reply"] = { post: op("AI: suggest a grounded reply (404 when AI is off)", params: [ case_id_param ]) }

      crud(result, "contacts", "Contact", extra_params: %w[q external_id organisation_id],
           create_note: "Contacts are addressable by numeric id or ext:{external_id}.")
      crud(result, "organisations", "Organisation")
      crud(result, "leads", "Lead", extra_params: %w[q status owner_id])
      result["/leads/{id}/convert"] = { post: op("Convert a lead — upserts/links a Contact and stamps the lead converted",
        params: [ id_param ], responses: { "200" => "Converted" }) }
      crud(result, "queues", "Queue", create_note: "Queues are addressable by id or slug.")
      crud(result, "categories", "Category")
      result["/categories/{id}/toggle_auto_resolve"] = { post: op("Flip AI auto-resolve for the category (admin user tokens only)", params: [ id_param ]) }
      crud(result, "sla_policies", "SlaPolicy")
      crud(result, "macros", "Macro")
      crud(result, "reference_docs", "ReferenceDoc")

      result["/users"] = {
        get: op("List users (admin, human tokens only)"),
        post: op("Create user (admin, human tokens only)", request: { user: :object })
      }
      result["/users/{id}"] = {
        get: op("Show user", params: [ id_param ]),
        patch: op("Update user", params: [ id_param ], request: { user: :object })
      }

      result["/api_tokens"] = {
        get: op("List per-user API tokens (admin)"),
        post: op("Issue a token — the raw value appears only in this response", request: { api_token: :object })
      }
      result["/api_tokens/{id}"] = { delete: op("Revoke a token", params: [ id_param ]) }

      result["/service_accounts"] = {
        get: op("List service accounts (admin, human tokens only)"),
        post: op("Create service account — client_secret appears only in this response", request: { service_account: :object })
      }
      result["/service_accounts/{id}"] = {
        get: op("Show service account", params: [ id_param ]),
        patch: op("Update name/scopes/active", params: [ id_param ], request: { service_account: :object }),
        delete: op("Deactivate and delete", params: [ id_param ])
      }
      result["/service_accounts/{id}/rotate_secret"] = { post: op("Rotate the client secret (revokes live tokens)", params: [ id_param ]) }

      result["/webhook_endpoints"] = {
        get: op("List webhook endpoints"),
        post: op("Create endpoint — signing secret appears only in this response", request: { webhook_endpoint: :object })
      }
      result["/webhook_endpoints/{id}"] = {
        get: op("Show endpoint", params: [ id_param ]),
        patch: op("Update endpoint", params: [ id_param ], request: { webhook_endpoint: :object }),
        delete: op("Delete endpoint", params: [ id_param ])
      }
      result["/webhook_endpoints/{id}/deliveries"] = { get: op("Delivery log for the endpoint", params: [ id_param ]) }

      result["/audit/entries"] = { get: op("List audit entries (admin or audit:read)", params: [
        query_param("action_name"), query_param("auditable_type"), query_param("auditable_id")
      ]) }
      result["/audit/verification"] = { get: op("Verify the audit hash chain end-to-end") }
      result["/reports/activity"] = { get: op(
        "Activity & Usage report: per-user action counts, login history, case volume by queue/staff, " \
        "resolution rate, SLA breach count and compliance, AI-vs-human reply split (admin or audit:read)",
        params: [ query_param("from"), query_param("to") ]) }

      result["/settings"] = {
        get: op("Read deployment settings (secrets masked)"),
        patch: op("Update deployment settings", request: { llm_provider: :string })
      }

      result
    end

    # -- helpers ---------------------------------------------------------

    def crud(result, path, schema, extra_params: [], create_note: nil)
      result["/#{path}"] = {
        get: op("List #{path.humanize.downcase}",
                params: [ query_param("page"), query_param("per_page") ] + extra_params.map { |p| query_param(p) },
                schema: schema),
        post: op([ "Create", create_note ].compact.join(". "), request: { path.singularize => :object }, schema: schema)
      }
      result["/#{path}/{id}"] = {
        get: op("Show", params: [ id_param ], schema: schema),
        patch: op("Update", params: [ id_param ], request: { path.singularize => :object }, schema: schema),
        delete: op("Delete (soft)", params: [ id_param ])
      }
    end

    def op(summary, params: [], request: nil, responses: nil, schema: nil, security: nil)
      operation = { summary: summary, parameters: params }
      operation[:security] = security unless security.nil?
      if request
        operation[:requestBody] = {
          content: { "application/json" => { schema: object_schema(**request) } }
        }
      end
      success = { description: "Success" }
      if schema
        success[:content] = { "application/json" => {
          schema: { type: "object", properties: { data: { "$ref" => "#/components/schemas/#{schema}" } } }
        } }
      end
      operation[:responses] = { "200" => success,
                                "403" => { description: "Forbidden" },
                                "401" => { description: "Unauthorized" } }
      (responses || {}).each { |code, desc| operation[:responses][code] = { description: desc } }
      operation
    end

    def id_param
      { name: "id", in: "path", required: true, schema: { type: "string" } }
    end

    def case_id_param
      { name: "case_id", in: "path", required: true, schema: { type: "string" } }
    end

    def query_param(name)
      { name: name, in: "query", required: false, schema: { type: "string" } }
    end

    def enum(values)
      { type: "string", enum: values.map(&:to_s) }
    end

    def object_schema(**properties)
      {
        type: "object",
        properties: properties.transform_values { |type| type_schema(type) }.transform_keys(&:to_s)
      }
    end

    def type_schema(type)
      case type
      when :integer then { type: "integer" }
      when :boolean then { type: "boolean" }
      when :datetime then { type: "string", format: "date-time" }
      when :object then { type: "object" }
      when :string then { type: "string" }
      when Hash then type
      else { type: "string" }
      end
    end
  end
end
