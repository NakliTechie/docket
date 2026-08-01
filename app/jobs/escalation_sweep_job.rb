# Recurring sweep (config/recurring.yml): advances open cases through their
# escalation levels. Idempotent via EscalationExecution, so overlapping runs are
# safe; attributed to the system (no actor).
class EscalationSweepJob < ApplicationJob
  queue_as :default

  def perform
    Current.set(actor: nil) do
      each_tenant_with_feature("service_desk") { CaseEscalation.run! }
    end
    record_sweep_success!
  end
end
