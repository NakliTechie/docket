module Connectors
  # Deny-by-default gate for agent-initiated actions. Two checks:
  #   1. the connector must EXPOSE the action to agents (enabled_actions), and
  #   2. the principal must hold the authority to invoke.
  # An AI agent is a ServiceAccount; its authority is the existing OAuth
  # scope `connectors:invoke`. Staff may invoke directly (admin/supervisor).
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
      case principal
      when ServiceAccount then principal.scope?("connectors:invoke")
      when User           then principal.role_admin? || principal.role_supervisor?
      else false
      end
    end
  end
end
