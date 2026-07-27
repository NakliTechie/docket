# Recurring sweep (config/recurring.yml): flags overdue first-response
# and resolution SLAs. Each flag flip is a normal audited case update,
# attributed to the system (no actor).
class SlaBreachSweepJob < ApplicationJob
  queue_as :default

  def perform
    Current.set(actor: nil) do
      each_tenant_with_feature("service_desk") do
        Case.overdue_first_response.find_each do |kase|
          kase.update!(first_response_breached: true)
          Webhooks.publish("case.sla_breached", Webhooks.case_payload(kase).merge(breach: "first_response"))
        end
        Case.overdue_resolution.find_each do |kase|
          kase.update!(resolution_breached: true)
          Webhooks.publish("case.sla_breached", Webhooks.case_payload(kase).merge(breach: "resolution"))
        end
      end
    end
    record_sweep_success!
  end
end
