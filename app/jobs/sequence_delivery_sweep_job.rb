# Recovery sweep for the transactional sequence outbox. Multiple enqueues are
# harmless: SequenceDeliveryJob atomically claims a pending row once.
class SequenceDeliverySweepJob < ApplicationJob
  queue_as :default

  def perform
    each_tenant_with_feature("crm.sequences") do
      SequenceDelivery.status_pending.find_each(&:enqueue!)
    end
    record_sweep_success!
  end
end
