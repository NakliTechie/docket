require "digest"

module Connectors
  # The agent dispatch loop — "AI runs the show" over the effector layer.
  # Gives an AI agent (a ServiceAccount) the connector actions it is
  # authorized for and lets it act on one case via OpenAI-style tool calling.
  #
  # Every tool call goes through Connectors::Invoke (authorize -> budget ->
  # approval gate -> execute), so a write / decision-of-record action is
  # QUEUED for a human, never run autonomously — the loop hands those off and
  # carries on (the "execute-autonomous + handoff-for-confirmation" pattern).
  # Bounded by MAX_STEPS; each step is logged on the case timeline.
  class AgentRunner
    MAX_STEPS = 6

    attr_reader :kase, :agent, :client

    def initialize(kase, agent:, client: Llm.client)
      @kase = kase
      @agent = agent
      @client = client
    end

    # Manual trigger seam: enqueue the loop off-request.
    def self.run_later(kase, agent:)
      Connectors::AgentRunnerJob.perform_later(kase.id, agent.id)
    end

    # The ServiceAccount designated (in Settings) to act as the case effector
    # agent — nil when none is set or it is inactive.
    def self.designated_agent
      id = Setting.get("effector_agent_id")
      id.present? ? ServiceAccount.active.find_by(id: id) : nil
    end

    # Whether a case can be handed to the agent right now: the AI layer is on
    # and an active agent is designated.
    def self.available?
      Llm.enabled? && designated_agent.present?
    end

    def run
      return if client.nil?
      tools = authorized_tools
      return if tools.empty?

      messages = [ system_message, user_message ]
      MAX_STEPS.times do
        reply = client.chat_with_tools(messages, tools: tools.map { |t| t[:spec] })
        messages << reply
        calls = Array(reply["tool_calls"] || reply[:tool_calls])
        if calls.empty?
          finalize(reply)
          break
        end
        calls.each do |call|
          messages << tool_result(call, dispatch(call, tools))
        end
      end
    rescue Llm::Error => e
      log_failure(e)
    end

    private

    # Active connectors this agent may invoke, each enabled action projected to
    # an OpenAI function tool and indexed by name so a returned call maps back
    # to (connector, action).
    def authorized_tools
      return [] unless agent.respond_to?(:scope?) && agent.scope?("connectors:invoke")

      Connector.active.flat_map do |connector|
        connector.enabled_actions.filter_map do |action_key|
          action = connector.provider_action(action_key)
          next unless action
          { name: tool_name(connector.id, action_key), connector: connector, action_key: action_key,
            spec: openai_tool(connector, action) }
        end
      end
    end

    def openai_tool(connector, action)
      {
        type: "function",
        function: {
          name: tool_name(connector.id, action.key),
          description: action.summary,
          parameters: action.params || { "type" => "object", "properties" => {} }
        }
      }
    end

    def tool_name(connector_id, action_key)
      "conn_#{connector_id}__#{action_key}"
    end

    # Run one tool call through the effector gate and return a JSON observation
    # the model can reason on.
    def dispatch(call, tools)
      fn = call["function"] || call[:function] || {}
      name = fn["name"] || fn[:name]
      tool = tools.find { |t| t[:name] == name }
      return error_obs("unknown tool: #{name}") unless tool

      args = parse_args(fn["arguments"] || fn[:arguments])
      invocation = Connectors::Invoke.call(
        tool[:connector], tool[:action_key],
        args: args, principal: agent, on_behalf_of: "case:#{kase.id}",
        reasoning: "Agent acting on case #{kase.id} via #{name}.",
        idempotency_key: "case-#{kase.id}-#{name}-#{Digest::SHA256.hexdigest(args.to_json)[0, 12]}"
      )
      log_step(invocation)
      observation(invocation)
    rescue Connectors::Error => e
      log_blocked(name, e)
      error_obs(e.message)
    end

    def observation(inv)
      case inv.status
      when "succeeded"
        { ok: true, result: inv.result }
      when "proposed"
        { queued_for_approval: true, invocation_id: inv.id, decision_class: inv.decision_class,
          note: "A human must approve this action before it runs. Do not retry it." }
      when "failed"
        { ok: false, error: inv.error }
      else
        { status: inv.status }
      end.to_json
    end

    # --- LLM message construction ---

    def system_message
      { role: "system", content: <<~SYS }
        You are an AI case-handling agent for a public grievance service desk. You act on ONE case by
        calling the available tools. #{Llm.fence_instruction}
        Rules:
        - Call a tool only when it genuinely advances resolving THIS case.
        - Read actions run immediately. Write or decision-of-record actions are QUEUED for a human to
          approve — you cannot complete those yourself; once a tool reports it is queued, move on and
          do not retry it.
        - When you have taken the actions you can, reply with a one-line summary and stop.
      SYS
    end

    def user_message
      body = kase.description.presence ||
             kase.messages.where(direction: :inbound).order(:created_at).first&.body.to_s
      { role: "user", content: <<~USR }
        Case ##{kase.id} (status: #{kase.status})
        Subject:
        #{Llm.fence(kase.subject)}
        Details:
        #{Llm.fence(body)}
      USR
    end

    def tool_result(call, observation)
      { role: "tool", tool_call_id: (call["id"] || call[:id]), content: observation }
    end

    def parse_args(raw)
      return {} if raw.blank?
      raw.is_a?(Hash) ? raw : JSON.parse(raw)
    rescue JSON::ParserError
      {}
    end

    # --- case-timeline logging (staff-only internal notes) ---

    def log_step(inv)
      key = { "succeeded" => "ran", "proposed" => "queued", "failed" => "failed_action" }
              .fetch(inv.status, "ran")
      note(I18n.t("connectors.agent.#{key}", action: inv.action),
           "invocation_id" => inv.id, "action" => inv.action,
           "decision_class" => inv.decision_class, "status" => inv.status)
    end

    def log_blocked(name, error)
      note(I18n.t("connectors.agent.blocked", action: name, reason: error.message), "blocked" => true)
    end

    def finalize(reply)
      text = (reply["content"] || reply[:content]).to_s.strip
      note(text, "summary" => true) if text.present?
    end

    def log_failure(error)
      note(I18n.t("connectors.agent.failed"), "error" => error.message)
    end

    def note(body, **metadata)
      kase.messages.create!(
        kind: :internal_note, direction: :outbound, author: nil,
        body: body, metadata: { "ai" => "effector" }.merge(metadata)
      )
    end

    def error_obs(message)
      { ok: false, error: message }.to_json
    end
  end
end
