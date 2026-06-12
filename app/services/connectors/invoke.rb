module Connectors
  # Runs ONE agent-initiated action — the outbound mirror of Connectors::Sync.
  # Orchestrates: authorize → idempotency short-circuit → budget → approval
  # gate → execute with the agent as the audit actor → record the observation.
  #
  #   inv = Connectors::Invoke.call(connector, "post_json",
  #           args: { "body" => { ... } }, principal: agent,
  #           on_behalf_of: "case:#{case.id}", reasoning: "citizen requested status",
  #           idempotency_key: "case-123-status")
  #
  # A :read action runs immediately. A :write / :irreversible action is parked
  # as :proposed for a human-of-record unless the connector auto-approves it;
  # Invoke.approve!(inv, approver:) then executes it.
  module Invoke
    module_function

    def call(connector, action_key, args:, principal:, on_behalf_of: nil,
             reasoning: nil, idempotency_key: nil)
      action = connector.provider_action(action_key)
      raise Connectors::Error, "unknown action: #{action_key}" unless action
      Authorization.permit!(principal: principal, connector: connector, action: action)

      if idempotency_key.present?
        existing = connector.invocations.find_by(idempotency_key: idempotency_key)
        return existing if existing
      end

      Budget.enforce!(principal)

      invocation = nil
      Current.set(actor: principal, on_behalf_of: on_behalf_of) do
        invocation = connector.invocations.create!(
          action: action.key, args: args, on_behalf_of: on_behalf_of,
          reasoning: reasoning, requested_by: principal, idempotency_key: idempotency_key,
          effect: action.effect, decision_class: action.effective_decision_class,
          status: gated_status(connector, action)
        )
        execute!(invocation, action) if invocation.status_approved?
      end
      invocation
    end

    # Human-of-record path: a staff approver releases a parked action. A
    # decision of record requires a reasoned order (substantive review — a
    # blank rubber-stamp is itself legally void under Indian admin law).
    def approve!(invocation, approver:, reason: nil)
      raise Connectors::Error, "invocation is not awaiting approval" unless invocation.status_proposed?
      if invocation.of_record? && reason.to_s.strip.blank?
        raise Connectors::Error, "a decision of record requires a reason (a reasoned order)"
      end
      invocation.update!(status: :approved, approved_by: approver, approved_at: Time.current,
                         decision_reason: reason.presence)
      action = invocation.connector.provider_action(invocation.action)
      execute!(invocation, action)
      invocation
    end

    def reject!(invocation, approver:)
      raise Connectors::Error, "invocation is not awaiting approval" unless invocation.status_proposed?
      invocation.update!(status: :rejected, approved_by: approver, approved_at: Time.current)
      invocation
    end

    # Route by accountability tier: autonomous runs unattended; a decision of
    # record ALWAYS parks for a human (auto-approve cannot bypass it); confirm
    # parks unless the connector auto-approves the action.
    def gated_status(connector, action)
      case action.effective_decision_class
      when :autonomous then :approved
      when :of_record  then :proposed
      else connector.auto_approves?(action.key) ? :approved : :proposed
      end
    end

    # The action is attributed to the agent (requested_by) in the audit chain,
    # acting on_behalf_of the case — even on the human-approved path, the human
    # owns the approval entry and the agent owns the execution.
    def execute!(invocation, action)
      invocation.update!(status: :executing)
      Current.set(actor: invocation.requested_by, on_behalf_of: invocation.on_behalf_of,
                  delegation_id: invocation.delegation_id) do
        observation = invocation.connector.provider_instance.invoke(
          action.key, invocation.args || {}, { invocation: invocation }
        )
        invocation.update!(status: :succeeded, result: observation, finished_at: Time.current)
      end
      invocation
    rescue StandardError => e
      invocation.update!(status: :failed, error: e.message.truncate(500), finished_at: Time.current)
      invocation
    end
  end
end
