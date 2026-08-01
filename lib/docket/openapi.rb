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
          "x-docket-version": Docket::VERSION,
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
            custom_fields: :object,
            merged_into_id: :integer, merged_at: :datetime,
            merged_case_ids: { type: "array", items: { type: "integer" } },
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
            sms_consent: :boolean, email_consent: :boolean, email_unsubscribed_at: :datetime,
            created_at: :datetime, updated_at: :datetime
          ),
          Organisation: object_schema(id: :integer, name: :string, kind: :string, external_ref: :string,
                                      notes: :string, created_at: :datetime, updated_at: :datetime),
          Lead: object_schema(id: :integer, name: :string, email: :string, phone: :string,
                              company_name: :string, source: enum(Lead.sources.keys), status: enum(Lead.statuses.keys),
                              owner_id: :integer, contact_id: :integer, converted_deal_id: :integer, value_estimate_cents: :integer,
                              notes: :string, sms_consent: :boolean, email_consent: :boolean,
                              email_unsubscribed_at: :datetime,
                              consent_captured_at: :datetime, consent_source: :string,
                              provenance: :object, merged_into_id: :integer, merged_at: :datetime,
                              merged_lead_ids: { type: "array", items: { type: "integer" } },
                              converted_at: :datetime, created_at: :datetime, updated_at: :datetime),
          LeadCaptureForm: object_schema(id: :integer, name: :string, slug: :string,
                                         field_mapping: :object, consent_disclosure: :string,
                                         active: :boolean, is_default: :boolean,
                                         created_at: :datetime, updated_at: :datetime),
          Deal: object_schema(id: :integer, name: :string, pipeline_id: :integer, pipeline_stage_id: :integer,
                              status: enum(Deal.statuses.keys), value_cents: :integer, currency: :string,
                              owner_id: :integer, contact_id: :integer, organisation_id: :integer, lead_id: :integer,
                              expected_close_on: :datetime, closed_at: :datetime,
                              lost_reason: enum(Deal.lost_reasons.keys), onboarding_project_id: :integer,
                              line_items_total_cents: :integer,
                              line_items: { type: "array", items: { type: "object" } },
                              competitors: { type: "array", items: { type: "object" } },
                              created_at: :datetime, updated_at: :datetime),
          Product: object_schema(id: :integer, name: :string, sku: :string, description: :string,
                                 default_unit_price_cents: :integer, currency: :string,
                                 active: :boolean, created_at: :datetime, updated_at: :datetime),
          Activity: object_schema(id: :integer, kind: enum(Activity.kinds.keys), title: :string, body: :string,
                                  subject_type: enum(Activity::SUBJECT_TYPES), subject_id: :integer,
                                  owner_id: :integer, due_at: :datetime, status: enum(Activity.statuses.keys),
                                  completed_at: :datetime, created_at: :datetime, updated_at: :datetime),
          DealLineItem: object_schema(id: :integer, deal_id: :integer, product_id: :integer,
                                      description: :string, quantity: :number,
                                      unit_price_cents: :integer, total_cents: :integer,
                                      currency: :string, created_at: :datetime, updated_at: :datetime),
          Competitor: object_schema(id: :integer, name: :string, website: :string, notes: :string,
                                    created_at: :datetime, updated_at: :datetime),
          DealCompetitor: object_schema(id: :integer, deal_id: :integer, competitor_id: :integer,
                                        competitor_name: :string, disposition: :string, notes: :string,
                                        created_at: :datetime, updated_at: :datetime),
          DealContactRole: object_schema(id: :integer, deal_id: :integer, contact_id: :integer,
                                         contact_name: :string, role: enum(DealContactRole.roles.keys),
                                         created_at: :datetime, updated_at: :datetime),
          Pipeline: object_schema(id: :integer, name: :string, slug: :string, position: :integer, active: :boolean,
                                  stages: { type: "array", items: { type: "object" } },
                                  created_at: :datetime, updated_at: :datetime),
          Sequence: object_schema(id: :integer, name: :string, active: :boolean,
                                  steps: { type: "array", items: { type: "object" } },
                                  created_at: :datetime, updated_at: :datetime),
          SequenceEnrollment: object_schema(id: :integer, sequence_id: :integer, enrollable_type: :string,
                                            enrollable_id: :integer, status: enum(SequenceEnrollment.statuses.keys),
                                            current_step_position: :integer, next_run_at: :datetime,
                                            last_delivery: :object,
                                            created_at: :datetime, updated_at: :datetime),
          Queue: object_schema(id: :integer, name: :string, slug: :string, description: :string,
                               member_ids: { type: "array", items: { type: "integer" } },
                               created_at: :datetime, updated_at: :datetime),
          Category: object_schema(id: :integer, name: :string, description: :string,
                                  ai_auto_resolve: :boolean, created_at: :datetime, updated_at: :datetime),
          SlaPolicy: object_schema(id: :integer, name: :string, description: :string,
                                   business_calendar_id: :integer,
                                   targets: { type: "array", items: { type: "object" } },
                                   created_at: :datetime, updated_at: :datetime),
          BusinessCalendar: object_schema(id: :integer, name: :string, time_zone: :string,
                                          is_default: :boolean,
                                          windows: { type: "array", items: { type: "object" } },
                                          exceptions: { type: "array", items: { type: "object" } },
                                          created_at: :datetime, updated_at: :datetime),
          CustomFieldDefinition: object_schema(
            id: :integer, resource_type: enum(CustomFieldDefinition::RESOURCE_TYPES),
            key: :string, label: :string, field_type: enum(CustomFieldDefinition::FIELD_TYPES),
            options: { type: "array", items: { type: "string" } }, required: :boolean,
            active: :boolean, reportable: :boolean, position: :integer,
            created_at: :datetime, updated_at: :datetime
          ),
          Macro: object_schema(id: :integer, name: :string, body: :string,
                               message_kind: :string, set_status: :string, set_priority: :string,
                               set_queue_id: :integer, set_assignee_id: :integer,
                               created_at: :datetime, updated_at: :datetime),
          ReferenceDoc: object_schema(id: :integer, title: :string, body: :string, created_at: :datetime, updated_at: :datetime),
          User: object_schema(id: :integer, name: :string, email_address: :string,
                              role: enum(User.roles.keys), active: :boolean, locale: :string,
                              email_signature: :string,
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
          Project: object_schema(id: :integer, key: :string, name: :string, description: :string,
                                 lead_id: :integer, archived: :boolean, visibility: :string,
                                 onboarding_deal_id: :integer, project_template_id: :integer,
                                 assignment_rules: { type: "array", items: { type: "object" } },
                                 created_at: :datetime, updated_at: :datetime),
          ProjectTemplate: object_schema(id: :integer, name: :string, key_prefix: :string,
                                         description: :string, active: :boolean,
                                         items: { type: "array", items: { type: "object" } },
                                         created_at: :datetime, updated_at: :datetime),
          WorkItem: object_schema(id: :integer, reference: :string, project_id: :integer, number: :integer,
                                  title: :string, description: :string, kind: :string, priority: :string,
                                  workflow_state_id: :integer, workflow_state: :string, state_category: :string,
                                  assignee_id: :integer, reporter_id: :integer, parent_id: :integer,
                                  sprint_id: :integer, labels: :object, estimate: :string,
                                  due_on: :datetime, custom_fields: :object,
                                  relations: { type: "array", items: { type: "object" } }, closed_at: :datetime,
                                  created_at: :datetime, updated_at: :datetime),
          WorkComment: object_schema(id: :integer, work_item_id: :integer,
                                     author_type: :string, author_id: :integer, body: :string,
                                     created_at: :datetime, updated_at: :datetime),
          Sprint: object_schema(id: :integer, project_id: :integer, name: :string, goal: :string,
                                status: :string, starts_on: :datetime, ends_on: :datetime,
                                created_at: :datetime, updated_at: :datetime),
          SprintReport: object_schema(
            project_id: :integer,
            cycle_time_days: { type: %w[number null] },
            sprints: { type: "array", items: { type: "object" } }
          ),
          Decision: object_schema(id: :integer, rule: :string, version: :string, signal: :string,
                                  decision_class: :string, status: enum(Decision.statuses.keys),
                                  action: :string, action_params: :object, effect: :string,
                                  recommendation: :string, reasoning: :string,
                                  subject_type: :string, subject_id: :integer, subject_label: :string,
                                  approved_by_id: :integer, decision_reason: :string, decided_at: :datetime,
                                  appealable: :boolean, created_at: :datetime, updated_at: :datetime),
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
      result["/mcp"] = {
        post: op("Model Context Protocol endpoint (JSON-RPC 2.0): initialize, tools/list, and tools/call " \
                 "expose every api/v1 operation as an MCP tool, under the same bearer auth, tenant and scopes.",
                 request: { jsonrpc: :string, id: :integer, method: :string, params: :object },
                 responses: { "200" => "JSON-RPC response", "202" => "Accepted (notification)" })
      }

      crud(result, "cases", "Case",
           extra_params: %w[q status priority queue_id assignee_id contact_id contact_external_id],
           create_note: "Service accounts may pass on_behalf_of (contact external_id) plus an optional contact{} for upsert, and message_body for the initial customer message. case[attachments]/case[files] attach to that initial message. Cases are addressable by numeric id or tracking ID.")
      result["/cases/{id}/transition"] = { post: op("Transition case status through the state machine",
        params: [ id_param ], request: { status: enum(Case.statuses.keys) },
        responses: { "200" => "Transitioned", "422" => "Illegal transition" }) }
      result["/cases/{id}/assign"] = { post: op("Assign or unassign the case",
        params: [ id_param ], request: { assignee_id: :integer }) }
      result["/cases/{id}/merge"] = { post: op(
        "Merge another same-contact case into this case", params: [ id_param ],
        request: { source_case_id: :integer }) }
      result["/cases/{id}/split"] = { post: op(
        "Move selected messages into a new same-contact case", params: [ id_param ],
        request: { subject: :string, message_ids: { type: "array", items: { type: "integer" } } }) }
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
      result["/leads/{id}/merge"] = { post: op(
        "Merge another reviewed lead into this canonical lead; the source remains in the audit lineage",
        params: [ id_param ], request: { source_lead_id: :integer }) }
      crud(result, "lead_capture_forms", "LeadCaptureForm",
           create_note: "Maps public field names to lead attributes and records consent provenance. Requires crm:write.")
      crud(result, "pipelines", "Pipeline")
      crud(result, "deals", "Deal", extra_params: %w[pipeline_id status])
      result["/deals/{id}/move"] = { post: op("Move a deal to another stage in its pipeline (the kanban drag)",
        params: [ id_param ], request: { pipeline_stage_id: :integer }, responses: { "200" => "Moved" }) }
      result["/deals/{id}/onboard"] = { post: op(
        "Idempotently create an onboarding project for a won deal from a project template",
        params: [ id_param ], request: { project_template_id: :integer }, schema: "Project",
        responses: { "201" => "Created", "422" => "Deal is not won or template is invalid" }) }
      result["/deals/{id}/engage"] = { post: op(
        "Idempotently create an engagement project (pre-quote studies) for an OPEN deal from a project template",
        params: [ id_param ], request: { project_template_id: :integer }, schema: "Project",
        responses: { "201" => "Created", "422" => "Deal is not open or template is invalid" }) }
      crud(result, "products", "Product")
      crud(result, "competitors", "Competitor")
      crud(result, "activities", "Activity", extra_params: %w[subject_type subject_id status owner_id],
           create_note: "activity[subject_type] is Contact/Lead/Deal/Case; activity[subject_id] the record it hangs off.")
      result["/activities/{id}/complete"] = { post: op("Mark an activity done", params: [ id_param ], schema: "Activity") }
      result["/deals/{deal_id}/line_items"] = { post: op(
        "Add a catalog product to a deal; all line-item currency must match the deal",
        params: [ path_param("deal_id") ], request: { deal_line_item: :object }, schema: "DealLineItem") }
      result["/deal_line_items/{id}"] = {
        patch: op("Update quantity or price", params: [ id_param ], request: { deal_line_item: :object },
                  schema: "DealLineItem"),
        delete: op("Remove a deal line item", params: [ id_param ])
      }
      result["/deals/{deal_id}/competitor_links"] = { post: op(
        "Link a competitor and disposition to a deal", params: [ path_param("deal_id") ],
        request: { deal_competitor: :object }, schema: "DealCompetitor") }
      result["/deal_competitors/{id}"] = {
        patch: op("Update competitor disposition", params: [ id_param ],
                  request: { deal_competitor: :object }, schema: "DealCompetitor"),
        delete: op("Remove a competitor link", params: [ id_param ])
      }
      result["/deals/{deal_id}/contact_roles"] = { post: op(
        "Assign a contact a role on a deal", params: [ path_param("deal_id") ],
        request: { deal_contact_role: :object }, schema: "DealContactRole") }
      result["/deal_contact_roles/{id}"] = {
        patch: op("Change a contact's role on a deal", params: [ id_param ],
                  request: { deal_contact_role: :object }, schema: "DealContactRole"),
        delete: op("Remove a contact role", params: [ id_param ])
      }
      # Work module (WM5). Documented here is what makes these reachable as MCP
      # tools too — the catalogue is derived from this document.
      crud(result, "projects", "Project", extra_params: %w[archived],
           create_note: "key is uppercase and unique per tenant; a new project seeds its default board columns. Service accounts need the work:manage scope for create/update/delete — configuring a workspace sits a tier above doing the work in it.")
      crud(result, "project_templates", "ProjectTemplate",
           create_note: "Reusable work-item checklist for explicit won-deal onboarding. Requires work:manage.")
      crud(result, "work_items", "WorkItem",
           extra_params: %w[project_id assignee_id sprint_id open],
           create_note: "work_item[project_id] is required on create. Identity is KEY-123, minted per project.")
      result["/work_items/{id}/transition"] = { post: op("Move a work item to another workflow state (audited; may return 202 when maker-checker approval is required)",
        params: [ id_param ], request: { workflow_state_id: :integer },
        responses: { "200" => "Moved", "202" => "Submitted for approval", "404" => "State not in this project" }) }
      result["/work_items/{work_item_id}/work_comments"] = {
        get: op("List comments on a work item", params: [ path_param("work_item_id") ], schema: "WorkComment"),
        post: op("Comment on a work item", params: [ path_param("work_item_id") ],
                 request: { work_comment: :object }, schema: "WorkComment")
      }
      result["/work_comments/{id}"] = {
        patch: op("Edit the caller's work comment", params: [ id_param ], request: { work_comment: :object },
                  schema: "WorkComment"),
        delete: op("Delete the caller's work comment", params: [ id_param ])
      }
      result["/work_items/{work_item_id}/relations"] = { post: op(
        "Relate work items as blocks or duplicates", params: [ path_param("work_item_id") ],
        request: { work_item_relation: :object }) }
      result["/work_item_relations/{id}"] = { delete: op(
        "Remove a work-item relation", params: [ id_param ]) }
      crud(result, "sprints", "Sprint", extra_params: %w[project_id], only: %i[index show create update],
           create_note: "sprint[project_id] is required on create. One sprint may be active per project. status is NOT settable here — close through POST /sprints/{id}/close so unfinished work is dealt with.")
      result["/projects/{project_id}/sprint_report"] = {
        get: op("Sprint velocity, commitment delivery, and median project cycle time",
                params: [ path_param("project_id") ], schema: "SprintReport")
      }
      result["/sprints/{id}/close"] = { post: op("Close a sprint; unfinished items go to the backlog or roll into roll_to",
        params: [ id_param ], request: { roll_to: :integer },
        responses: { "200" => "Closed, with moved_items count" }) }

      crud(result, "sequences", "Sequence")
      result["/sequence_enrollments"] = {
        get: op("List sequence enrollments", params: [ query_param("sequence_id") ], schema: "SequenceEnrollment"),
        post: op("Enroll a Lead or Contact in a sequence",
                 request: { sequence_id: :integer, enrollable_type: :string, enrollable_id: :integer },
                 schema: "SequenceEnrollment")
      }
      result["/sequence_enrollments/{id}"] = { get: op("Show enrollment", params: [ id_param ], schema: "SequenceEnrollment") }
      result["/sequence_enrollments/{id}/cancel"] = { post: op("Cancel an active enrollment", params: [ id_param ]) }
      crud(result, "queues", "Queue", create_note: "Queues are addressable by id or slug.")
      crud(result, "categories", "Category")
      result["/categories/{id}/toggle_auto_resolve"] = { post: op("Flip AI auto-resolve for the category (admin user tokens only)", params: [ id_param ]) }
      crud(result, "sla_policies", "SlaPolicy")
      crud(result, "business_calendars", "BusinessCalendar")
      crud(result, "custom_fields", "CustomFieldDefinition", extra_params: %w[resource_type],
           only: %i[index show create update],
           create_note: "resource_type is cases or work_items; key is immutable after creation. Deactivate a field to preserve historical values.")
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

      result["/decisions"] = { get: op(
        "List decisioning proposals — the contestability history. Filter by status or decision_class. " \
        "Human token only (invocation:review); the decisioning review surface is not exposed to service accounts.",
        params: [ query_param("page"), query_param("per_page"), query_param("status"), query_param("decision_class") ],
        schema: "Decision") }
      result["/decisions/run"] = { post: op(
        "Run the decisioning rule engine: persist proposals and auto-apply the autonomous ones",
        responses: { "200" => "Ran; returns the resulting decisions" }) }
      result["/decisions/{id}"] = { get: op("Show one decision", params: [ id_param ], schema: "Decision") }
      result["/decisions/{id}/approve"] = { post: op(
        "Approve a parked confirm/of_record proposal and apply it (a decision of record requires a reason)",
        params: [ id_param ], request: { reason: :string },
        responses: { "200" => "Approved and applied", "422" => "Not awaiting confirmation, or missing reason" }) }
      result["/decisions/{id}/reject"] = { post: op(
        "Reject a parked proposal", params: [ id_param ],
        responses: { "200" => "Rejected", "422" => "Not awaiting confirmation" }) }

      result["/audit/entries"] = { get: op("List audit entries (admin or audit:read)", params: [
        query_param("action_name"), query_param("auditable_type"), query_param("auditable_id")
      ]) }
      result["/audit/verification"] = { get: op("Verify the audit hash chain end-to-end") }
      result["/reports/activity"] = { get: op(
        "Activity & Usage report: per-user action counts, login history, case volume by queue/staff, " \
        "resolution rate, SLA breach count and compliance, AI-vs-human reply split (admin or audit:read)",
        params: [ query_param("from"), query_param("to") ]) }
      result["/reports/custom_fields"] = { get: op(
        "Distribution report for one reportable case or work-item custom field",
        params: [ query_param("resource_type"), query_param("field") ]) }
      result["/reports/csat"] = { get: op(
        "CSAT invitations, response rate, average, and score distribution",
        params: [ query_param("from"), query_param("to") ]) }
      result["/reports/sales"] = { get: op(
        "Currency-separated pipeline, win/loss, competitor losses, and velocity",
        params: [ query_param("from"), query_param("to") ]) }

      result["/settings"] = {
        get: op("Read deployment settings (secrets masked)"),
        patch: op("Update deployment settings", request: { llm_provider: :string })
      }

      result
    end

    # -- helpers ---------------------------------------------------------

    # `only:` narrows the documented verbs for resources that do not expose the
    # full set — documenting a route that does not exist is as wrong as omitting
    # one that does.
    def crud(result, path, schema, extra_params: [], create_note: nil,
             only: %i[index show create update destroy])
      collection = {}
      collection[:get] = op("List #{path.humanize.downcase}",
                            params: [ query_param("page"), query_param("per_page") ] +
                                    extra_params.map { |p| query_param(p) },
                            schema: schema) if only.include?(:index)
      collection[:post] = op([ "Create", create_note ].compact.join(". "),
                             request: { path.singularize => :object }, schema: schema) if only.include?(:create)
      result["/#{path}"] = collection if collection.any?

      member = {}
      member[:get] = op("Show", params: [ id_param ], schema: schema) if only.include?(:show)
      member[:patch] = op("Update", params: [ id_param ], request: { path.singularize => :object },
                          schema: schema) if only.include?(:update)
      member[:delete] = op("Delete (soft)", params: [ id_param ]) if only.include?(:destroy)
      result["/#{path}/{id}"] = member if member.any?
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
      path_param("id")
    end

    def case_id_param
      path_param("case_id")
    end

    def path_param(name)
      { name: name, in: "path", required: true, schema: { type: "string" } }
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
