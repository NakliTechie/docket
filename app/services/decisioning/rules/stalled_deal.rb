module Decisioning
  module Rules
    # Open deals sitting in their current stage past a dwell threshold → flag for
    # review. Built on the audit-mined DealStageHistory. Flagging is reversible
    # analysis → :autonomous.
    class StalledDeal < Decisioning::Rule
      DWELL_LIMIT = 14.days

      def self.decision_class = :autonomous

      def evaluate
        Deal.open_deals.find_each.filter_map do |deal|
          current = DealStageHistory.new(deal).segments.last
          next unless current&.open?

          dwell = current.dwell_seconds
          next if dwell < DWELL_LIMIT.to_i # seconds vs seconds, not Numeric vs Duration (L11)

          days = (dwell / 86_400).round
          decision(
            subject: deal,
            signal: "stalled_deal",
            recommendation: "Review — stalled #{days} days in its current stage.",
            reasoning: "current-stage dwell #{days}d ≥ #{(DWELL_LIMIT / 1.day).to_i}d threshold"
          )
        end
      end
    end
  end
end
