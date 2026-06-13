# Reconstructs a deal's stage timeline from the audit log — there is no
# dedicated stage-transition table, but every pipeline_stage_id change is
# already captured in a hash-chained AuditEntry (changeset
# {"pipeline_stage_id" => [old, new]}). This is the zero-migration path to
# pipeline velocity / stage-dwell analytics the decisioning dossier called for.
class DealStageHistory
  # One contiguous spell in a stage. left_at is nil while the deal is still in
  # the stage (an open deal's current stage) — dwell measures up to "now" then.
  Segment = Struct.new(:stage_id, :entered_at, :left_at, keyword_init: true) do
    def dwell_seconds
      ((left_at || Time.current) - entered_at).to_f
    end

    def open? = left_at.nil?
  end

  def initialize(deal)
    @deal = deal
  end

  # Chronological [Segment, …]: each stage spell with its entry/exit times.
  def segments
    @segments ||= begin
      entries = stage_entries
      entries.each_with_index.map do |(stage_id, entered_at), i|
        left_at = entries[i + 1]&.last || @deal.closed_at
        Segment.new(stage_id: stage_id, entered_at: entered_at, left_at: left_at)
      end
    end
  end

  private

  # [[stage_id, entered_at], …] in order, with consecutive same-stage spells
  # collapsed (an update that didn't move the stage isn't a transition).
  def stage_entries
    rows = AuditEntry
           .where(auditable_type: "Deal", auditable_id: @deal.id, action: %w[deal.create deal.update])
           .order(:id)
           .filter_map do |entry|
      change = entry.changeset.is_a?(Hash) ? entry.changeset["pipeline_stage_id"] : nil
      next unless change.is_a?(Array)
      stage_id = change.last
      [ stage_id, entry.created_at ] if stage_id
    end
    rows.chunk_while { |a, b| a.first == b.first }.map(&:first)
  end
end
