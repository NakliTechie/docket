module Mcp
  module Workflows
    DEFINITIONS = {
      "triage_case" => {
        description: "Assess a case, propose routing and priority, and preserve human confirmation gates.",
        arguments: [ { "name" => "case_id", "description" => "Case numeric ID or tracking ID", "required" => true } ],
        template: lambda { |args|
          <<~PROMPT
            Triage Docket case #{args.fetch("case_id")}.
            1. Read the case with get_cases_id and its messages with get_cases_case_id_messages.
            2. Read the linked contact with get_contacts_id when present.
            3. Summarize the customer need, urgency, SLA state, and missing information.
            4. Recommend a queue, assignee, category, priority, and next status.
            5. Before any write, state the exact change and respect Docket's confirmation or approval gates.
          PROMPT
        }
      },
      "resolve_case" => {
        description: "Develop a grounded resolution and record the approved customer response.",
        arguments: [ { "name" => "case_id", "description" => "Case numeric ID or tracking ID", "required" => true } ],
        template: lambda { |args|
          <<~PROMPT
            Resolve Docket case #{args.fetch("case_id")} without inventing facts.
            1. Read the case and messages.
            2. Use post_cases_case_id_assist_summarise and post_cases_case_id_assist_suggest_reply when available.
            3. Search published reference documents for grounded guidance.
            4. Present the proposed reply and transition before writing.
            5. Record the approved reply with post_cases_case_id_messages, then transition only through a legal state change.
          PROMPT
        }
      },
      "customer_360" => {
        description: "Build an evidence-backed customer view across service, CRM, and work history.",
        arguments: [ { "name" => "contact_id", "description" => "Contact numeric ID", "required" => true } ],
        template: lambda { |args|
          <<~PROMPT
            Build a Customer 360 brief for Docket contact #{args.fetch("contact_id")}.
            Read get_contacts_id first, then retrieve related cases, organisations, leads, deals, and work records exposed by the contact response.
            Separate observed facts from recommendations.
            Highlight open commitments, recent communications, SLA risk, churn or VIP labels, and the next owner action.
            Do not mutate records unless the user asks for a named change.
          PROMPT
        }
      },
      "qualify_lead" => {
        description: "Qualify a lead, explain the score, and advance or convert with traceable evidence.",
        arguments: [ { "name" => "lead_id", "description" => "Lead numeric ID", "required" => true } ],
        template: lambda { |args|
          <<~PROMPT
            Qualify Docket lead #{args.fetch("lead_id")}.
            Read get_leads_id and supporting contact, activity, campaign, and pipeline context.
            Explain the current score and score band from recorded signals.
            Recommend the next activity, routing, and stage.
            Use post_leads_id_convert only after the user confirms conversion and required data is present.
          PROMPT
        }
      },
      "review_decisions" => {
        description: "Review proposed decisions and appeals using maker-checker controls.",
        arguments: [ { "name" => "decision_id", "description" => "Optional decision ID; omit to review the queue", "required" => false } ],
        template: lambda { |args|
          target = args["decision_id"].present? ? "decision #{args['decision_id']}" : "the pending decision queue"
          <<~PROMPT
            Review #{target} in Docket.
            Read the decision, subject record, recommendation, reasoning, decision class, and appeal history.
            Test the recommendation against current record state before action.
            Distinguish approve, reject, and request-more-evidence outcomes.
            Never approve and originate the same maker-checker action as one identity.
          PROMPT
        }
      },
      "operational_health" => {
        description: "Summarize service, CRM, decision-quality, and work health for a date range.",
        arguments: [
          { "name" => "from", "description" => "Start date in YYYY-MM-DD", "required" => true },
          { "name" => "to", "description" => "End date in YYYY-MM-DD", "required" => true }
        ],
        template: lambda { |args|
          <<~PROMPT
            Produce Docket operational health from #{args.fetch("from")} through #{args.fetch("to")}.
            Use get_reports_activity, get_reports_csat, get_reports_sales, and available sprint reports.
            Include per-rule decision approval, rejection, and override rates from the operational dashboard data.
            Report counts with their date windows.
            Identify the three highest-impact follow-ups and name an accountable role for each.
          PROMPT
        }
      }
    }.freeze

    module_function

    def list
      DEFINITIONS.map do |name, definition|
        {
          "name" => name,
          "description" => definition.fetch(:description),
          "arguments" => definition.fetch(:arguments)
        }
      end
    end

    def get(name, arguments = {})
      definition = DEFINITIONS[name.to_s]
      raise Mcp::Error.new(-32602, "unknown prompt: #{name}") unless definition

      args = arguments.to_h.stringify_keys
      missing = definition.fetch(:arguments).filter_map do |argument|
        argument["name"] if argument["required"] && args[argument["name"]].blank?
      end
      raise Mcp::Error.new(-32602, "missing prompt arguments: #{missing.join(', ')}") if missing.any?

      {
        "description" => definition.fetch(:description),
        "messages" => [
          { "role" => "user", "content" => { "type" => "text", "text" => definition.fetch(:template).call(args) } }
        ]
      }
    end

    def markdown
      DEFINITIONS.map do |name, definition|
        arguments = definition.fetch(:arguments).map { |argument| argument["name"] }.join(", ")
        "## #{name}\n\n#{definition.fetch(:description)}\n\nArguments: #{arguments.presence || 'none'}"
      end.join("\n\n")
    end
  end
end
