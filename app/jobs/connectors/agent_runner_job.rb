module Connectors
  # Runs the agent dispatch loop off the request thread. Enqueue via
  # Connectors::AgentRunner.run_later(kase, agent:). Deliberately NOT wired
  # into case intake yet — which agent runs on which cases is a product +
  # settings decision (a designated effector ServiceAccount, gated by a
  # Setting), left as a considered follow-up.
  class AgentRunnerJob < ApplicationJob
    queue_as :default

    def perform(case_id, agent_id)
      kase = Case.find_by(id: case_id)
      agent = ServiceAccount.active.find_by(id: agent_id)
      return unless kase && agent

      Connectors::AgentRunner.new(kase, agent: agent).run
    end
  end
end
