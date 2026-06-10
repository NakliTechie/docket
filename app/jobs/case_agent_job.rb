class CaseAgentJob < ApplicationJob
  queue_as :default

  def perform(kase)
    Current.set(actor: nil) do
      CaseAgent.new(kase).run
    end
  end
end
