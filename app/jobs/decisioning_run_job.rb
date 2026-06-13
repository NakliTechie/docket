# Recurring (config/recurring.yml): runs the decisioning engine so autonomous
# decisions apply and confirm/of_record ones land in the approval queue — without
# anyone pressing the dashboard "Run" button. Per-tenant in a shared deploy (and
# the single tenant in isolated), attributed to the system (no actor).
class DecisioningRunJob < ApplicationJob
  queue_as :default

  def perform
    Current.set(actor: nil) do
      each_active_tenant { Decisioning::Dispatcher.run! }
    end
  end
end
