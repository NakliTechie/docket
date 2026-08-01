module Exports
  # Serialises Docket grievance cases back into a CPGRAMS-shaped payload — the
  # status + Action-Taken-Report round-trip a department uploads to CPGRAMS. By
  # default it covers only cases that came in from CPGRAMS (external_id prefix),
  # so re-export is idempotent and never leaks non-CPGRAMS cases.
  class Cpgrams
    EXTERNAL_PREFIX = "cpgrams:".freeze

    # Docket case status → CPGRAMS lifecycle vocabulary (the inverse of the
    # importer's STATUS_MAP; several Docket states fold onto "Under Process").
    STATUS_MAP = {
      "new" => "Receipt", "triaged" => "Under Process", "in_progress" => "Under Process",
      "waiting_on_customer" => "Awaiting Citizen", "reopened" => "Under Process",
      "resolved" => "Disposed of", "closed" => "Closed"
    }.freeze

    def self.call(...) = new(...).call

    def initialize(scope: nil, now: Time.current)
      @scope = scope || Case.where("external_id LIKE ?", "#{EXTERNAL_PREFIX}%")
      @now = now
    end

    def call
      {
        "generated_at" => @now.iso8601,
        "grievances" => @scope.canonical.includes(:messages).map { |kase| grievance(kase) }
      }
    end

    def to_json(*) = JSON.pretty_generate(call)

    private

    def grievance(kase)
      {
        "registration_number" => kase.external_id.to_s.delete_prefix(EXTERNAL_PREFIX),
        "status" => STATUS_MAP.fetch(kase.status, "Under Process"),
        "disposed_on" => (kase.resolved_at || kase.closed_at)&.iso8601,
        "action_taken_report" => latest_atr(kase),
        "docket_case_id" => kase.id,
        "docket_tracking_id" => kase.tracking_id
      }.compact
    end

    # The most recent public reply is the citizen-facing action taken. Read from
    # the preloaded association so the export stays one query.
    def latest_atr(kase)
      kase.messages
          .select { |message| message.kind == "public_reply" && message.direction == "outbound" }
          .max_by(&:created_at)&.body
    end
  end
end
