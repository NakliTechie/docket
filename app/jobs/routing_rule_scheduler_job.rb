# Evaluates elapsed-time routing rules once per case status episode. The
# execution ledger makes overlapping scheduler processes idempotent.
class RoutingRuleSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    Current.set(actor: nil) do
      each_tenant_with_feature("service_desk") { ScheduledCaseRouting.run! }
    end
    record_sweep_success!
  end
end
