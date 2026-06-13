module Connectors
  # Budgeted autonomy: a per-principal blast-radius limit. Caps how many
  # connector actions an agent may INITIATE within a rolling window — the
  # research-prescribed "first-class invariant" that prevents unbounded
  # agentic behaviour. Only ServiceAccount principals carry a budget; a nil
  # budget is unlimited. Idempotent retries short-circuit upstream and never
  # reach here, so a retry never consumes budget. Exceeding the budget is a
  # fail-safe deny — the action is not created.
  module Budget
    class Exceeded < Connectors::Error; end

    module_function

    def enforce!(principal)
      return unless principal.respond_to?(:effector_budgeted?) && principal.effector_budgeted?

      limit = principal.action_budget
      window = principal.effector_budget_window_minutes
      used = ConnectorInvocation
               .where(requested_by: principal)
               .where(created_at: window.minutes.ago..)
               .count
      return if used < limit

      raise Exceeded, "action budget exhausted (#{used}/#{limit} in #{window} min)"
    end

    # Per-connector cap: how many actions may flow through THIS connector in its
    # window, regardless of which agent initiates them (e.g. ≤10 refunds/hour
    # through the payments connector). nil budget = unlimited. Same fail-safe
    # deny as the per-principal cap.
    def enforce_connector!(connector)
      return unless connector.respond_to?(:effector_budgeted?) && connector.effector_budgeted?

      limit = connector.action_budget
      window = connector.effector_budget_window_minutes
      used = ConnectorInvocation
               .where(connector: connector)
               .where(created_at: window.minutes.ago..)
               .count
      return if used < limit

      raise Exceeded, "connector action budget exhausted (#{used}/#{limit} in #{window} min)"
    end
  end
end
