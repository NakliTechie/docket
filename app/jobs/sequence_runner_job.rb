# Recurring sweep (config/recurring.yml): advances every due sequence
# enrollment — sends the step that's come due through the comms gateway,
# schedules the next, completes when the steps run out. Attributed to the
# system (no actor), like the SLA sweep.
class SequenceRunnerJob < ApplicationJob
  queue_as :default

  def perform
    Current.set(actor: nil) do
      SequenceEnrollment.due.find_each(&:advance!)
    end
  end
end
