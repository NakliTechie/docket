module Connectors
  # Deny-by-default gate for agent-initiated actions. Two checks:
  #   1. the connector must EXPOSE the action to agents (enabled_actions), and
  #   2. the principal must hold the authority to invoke.
  # An AI agent is a ServiceAccount; its authority is the existing OAuth
  # scope `connectors:invoke`. Staff invoke via the matching console
  # permission (`connector:invoke`), so the effector gate and the console agree.
  module Authorization
    class Forbidden < Connectors::Error; end

    module_function

    def permit!(principal:, connector:, action:)
      unless connector.enabled_action?(action.key)
        raise Forbidden, "connector #{connector.id} does not expose action '#{action.key}'"
      end
      unless may_invoke?(principal)
        raise Forbidden, "#{principal.class.name} is not permitted to invoke connector actions"
      end
      true
    end

    def may_invoke?(principal)
      # Entitlement first, for EVERY principal. Checking it only inside
      # User#can? left the gate asymmetric: disabling the connectors module
      # stopped staff but not the service account — which is the principal the
      # AI agent actually runs as, so the module kept acting for a tenant that
      # doesn't have it.
      return false unless Features.enabled?("connectors")

      case principal
      when ServiceAccount then principal.scope?("connectors:invoke")
      when User           then principal.can?("connector:invoke")
      else false
      end
    end
  end
end
