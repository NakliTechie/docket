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
          status: gated_status(connector, action)
        )
        execute!(invocation, action) if invocation.status_approved?
      end
      invocation
    end

    # Human-of-record path: a staff approver releases a parked action.
    def approve!(invocation, approver:)
      raise Connectors::Error, "invocation is not awaiting approval" unless invocation.status_proposed?
      invocation.update!(status: :approved, approved_by: approver, approved_at: Time.current)
      action = invocation.connector.provider_action(invocation.action)
      execute!(invocation, action)
      invocation
    end

    def reject!(invocation, approver:)
      raise Connectors::Error, "invocation is not awaiting approval" unless invocation.status_proposed?
      invocation.update!(status: :rejected, approved_by: approver, approved_at: Time.current)
      invocation
    end

    # :read runs unattended; a write runs only if the connector auto-approves
    # it, otherwise it parks as :proposed for a human.
    def gated_status(connector, action)
      return :approved unless action.requires_approval?
      connector.auto_approves?(action.key) ? :approved : :proposed
    end

    # The action is attributed to the agent (requested_by) in the audit chain,
    # acting on_behalf_of the case — even on the human-approved path, the human
    # owns the approval entry and the agent owns the execution.
    def execute!(invocation, action)
      invocation.update!(status: :executing)
      Current.set(actor: invocation.requested_by, on_behalf_of: invocation.on_behalf_of) do
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
