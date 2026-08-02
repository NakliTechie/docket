module Decisioning
  module Rules
    class ConversationReply < Decisioning::Rule
      WINDOW = 30.days

      def self.decision_class = :confirm
      def self.effect = :write
      def self.owner_feature = "crm"

      def evaluate
        Deal.open_deals.find_each.filter_map do |deal|
          message = CrmMessage.where(subject: deal, direction: :inbound)
                              .where(occurred_at: WINDOW.ago..)
                              .recent_first.first
          next unless message

          next_stage = deal.pipeline.pipeline_stages
                           .where("position > ?", deal.pipeline_stage.position)
                           .order(:position, :id).detect { |stage| !stage.terminal? }
          next unless next_stage

          decision(
            subject: deal,
            signal: "customer_replied",
            recommendation: "Advance to #{next_stage.name} after reviewing the customer's reply.",
            reasoning: "inbound CRM message ##{message.id} at #{message.occurred_at.utc.iso8601}",
            action: :advance_deal_stage,
            action_params: { "pipeline_stage_id" => next_stage.id, "crm_message_id" => message.id }
          )
        end
      end
    end
  end
end
