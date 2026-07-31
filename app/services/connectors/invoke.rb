module Connectors
  # Runs ONE agent-initiated action — the outbound mirror of Connectors::Sync.
  # Orchestrates: authorize → idempotency short-circuit → budget → approval
  # gate → execute with the agent as the audit actor → record the observation.
  #
  #   inv = Connectors::Invoke.call(connector, "post_json",
  #           args: { "body" => { ... } }, principal: agent,
  #           on_behalf_of: "case:#{case.id}", reasoning: "customer requested status",
  #           idempotency_key: "case-123-status")
  #
  # A :read action runs immediately. A :write / :irreversible action is parked
  # as :proposed for a human-of-record unless the connector auto-approves it;
  # Invoke.approve!(inv, approver:) then executes it.
  module Invoke
    module_function

    # A reply already authored and authorized through the case surface must not
    # be parked behind a second approval click. It still crosses the governed
    # egress seam: operational state, connector/principal budgets, durable
    # idempotency, actor attribution, and the audited invocation record all
    # apply. Callers are responsible for authorizing the underlying reply.
    def call_direct(connector, action_key, args:, principal:, on_behalf_of: nil,
                    reasoning: nil, idempotency_key: nil)
      action = connector.provider_action(action_key)
      raise Connectors::Error, "unknown action: #{action_key}" unless action

      existing = connector.invocations.find_by(idempotency_key: idempotency_key) if idempotency_key.present?
      return existing if existing

      unless connector.operational?
        return create_direct_failure(
          connector, action, args, principal, on_behalf_of, reasoning, idempotency_key,
          "connector #{connector.id} is not active and configured"
        )
      end

      created = false
      invocation = Current.set(actor: principal, on_behalf_of: on_behalf_of) do
        Budget.reserve!(principal, connector) do
          existing = connector.invocations.find_by(idempotency_key: idempotency_key) if idempotency_key.present?
          next existing if existing

          created = true
          connector.invocations.create!(
            action: action.key, args: args, on_behalf_of: on_behalf_of,
            reasoning: reasoning, requested_by: principal, idempotency_key: idempotency_key,
            effect: action.effect, decision_class: action.effective_decision_class,
            status: :executing
          )
        end
      end
      created ? execute_claimed!(invocation, action) : invocation
    rescue ActiveRecord::RecordNotUnique
      raise unless idempotency_key.present?

      connector.invocations.find_by!(idempotency_key: idempotency_key)
    end

    def call(connector, action_key, args:, principal:, on_behalf_of: nil,
             reasoning: nil, idempotency_key: nil)
      action = connector.provider_action(action_key)
      raise Connectors::Error, "unknown action: #{action_key}" unless action
      Authorization.permit!(principal: principal, connector: connector, action: action)

      if idempotency_key.present?
        existing = connector.invocations.find_by(idempotency_key: idempotency_key)
        return existing if existing
      end

      invocation = Current.set(actor: principal, on_behalf_of: on_behalf_of) do
        Budget.reserve!(principal, connector) do
          # A concurrent idempotent request may have committed while this
          # caller waited for a budget lock. Recheck before consuming a slot.
          existing = connector.invocations.find_by(idempotency_key: idempotency_key) if idempotency_key.present?
          next existing if existing

          connector.invocations.create!(
            action: action.key, args: args, on_behalf_of: on_behalf_of,
            reasoning: reasoning, requested_by: principal, idempotency_key: idempotency_key,
            effect: action.effect, decision_class: action.effective_decision_class,
            status: gated_status(connector, action)
          )
        end
      end
      execute!(invocation, action) if invocation.status_approved?
      invocation
    rescue ActiveRecord::RecordNotUnique
      # Lost an idempotency-key race with a concurrent unbudgeted call —
      # return the winner instead of bubbling a 500. nil keys are distinct
      # in the unique index, so this is only safe for a real key.
      raise unless idempotency_key.present?
      invocation = connector.invocations.find_by(idempotency_key: idempotency_key)
      invocation
    end

    # Human-of-record path: a staff approver releases a parked action. A
    # decision of record requires a reasoned order (substantive review — a
    # blank rubber-stamp is itself legally void under Indian admin law).
    def approve!(invocation, approver:, reason: nil)
      action = nil
      invocation.with_lock do
        # A competing approver already owns execution. Reload and return the
        # winner's state without performing the external side effect again.
        return invocation.reload unless invocation.status_proposed?

        ensure_distinct_human!(invocation.requested_by, approver)
        if invocation.of_record? && reason.to_s.strip.blank?
          raise Connectors::Error, "a decision of record requires a reason (a reasoned order)"
        end
        action = invocation.connector.provider_action(invocation.action)
        # The provider catalogue can change between parking and approval
        # (action renamed/removed) — fail clearly before claiming execution.
        raise Connectors::Error, "action no longer offered: #{invocation.action}" unless action

        invocation.update!(status: :approved, approved_by: approver, approved_at: Time.current,
                           decision_reason: reason.presence)
        invocation.update!(status: :executing)
      end
      execute_claimed!(invocation, action)
    end

    def reject!(invocation, approver:, reason: nil)
      invocation.with_lock do
        return invocation.reload unless invocation.status_proposed?

        ensure_distinct_human!(invocation.requested_by, approver)
        if invocation.of_record? && reason.to_s.strip.blank?
          raise Connectors::Error, "a decision of record requires a reason (a reasoned order)"
        end
        invocation.update!(status: :rejected, approved_by: approver, approved_at: Time.current,
                           decision_reason: reason.presence)
      end
      invocation
    end

    # Route by accountability tier: autonomous runs unattended; a decision of
    # record ALWAYS parks for a human (auto-approve cannot bypass it); confirm
    # parks unless the connector auto-approves the action. A maker-checker
    # ApprovalProcess (PG4) escalates ANY covered action to review, overriding
    # the connector's auto-approve.
    def gated_status(connector, action)
      return :proposed if ApprovalGate.requires_action_review?(action.key)

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
      invocation.with_lock do
        return invocation.reload unless invocation.status_approved?
        invocation.update!(status: :executing)
      end
      execute_claimed!(invocation, action)
    end

    def execute_claimed!(invocation, action)
      Current.set(actor: invocation.requested_by, on_behalf_of: invocation.on_behalf_of,
                  delegation_id: invocation.delegation_id) do
        unless invocation.connector.operational?
          raise Connectors::Error, "connector #{invocation.connector_id} is not active and configured"
        end
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

    def ensure_distinct_human!(maker, checker)
      return unless maker.is_a?(User) && checker.is_a?(User)
      return unless maker.persisted? && checker.persisted?
      return unless maker.id == checker.id

      raise Connectors::Error, "the maker cannot approve or reject their own invocation"
    end

    def create_direct_failure(connector, action, args, principal, on_behalf_of, reasoning,
                              idempotency_key, error)
      Current.set(actor: principal, on_behalf_of: on_behalf_of) do
        connector.invocations.create!(
          action: action.key, args: args, on_behalf_of: on_behalf_of,
          reasoning: reasoning, requested_by: principal, idempotency_key: idempotency_key,
          effect: action.effect, decision_class: action.effective_decision_class,
          status: :failed, error: error, finished_at: Time.current
        )
      end
    end
    private_class_method :create_direct_failure

    private_class_method :ensure_distinct_human!
  end
end
