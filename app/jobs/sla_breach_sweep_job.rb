# Recurring sweep (config/recurring.yml): flags overdue first-response
# and resolution SLAs. Each flag flip is a normal audited case update,
# attributed to the system (no actor).
class SlaBreachSweepJob < ApplicationJob
  queue_as :default

  def perform
    Current.set(actor: nil) do
      each_tenant_with_feature("service_desk") do
        Case.overdue_first_response.find_each do |kase|
          record_breach!(kase, :first_response)
        end
        Case.overdue_resolution.find_each do |kase|
          record_breach!(kase, :resolution)
        end
      end
    end
    record_sweep_success!
  end

  private

  # The flag, clock evidence, notification outbox and webhook outbox commit as
  # one unit. Jobs created by those outboxes enqueue after commit, so a later
  # sweep can recover delivery without ever losing the durable consequence.
  def record_breach!(kase, clock)
    flag = "#{clock}_breached"
    kase.with_lock do
      return if kase.public_send(flag)

      kase.update!(flag => true)
      SlaClock.breach!(kase, clock)
      Notifications::Events.sla_breach(kase, clock)
      Webhooks.publish("case.sla_breached", Webhooks.case_payload(kase).merge(breach: clock.to_s))
    end
  end
end
