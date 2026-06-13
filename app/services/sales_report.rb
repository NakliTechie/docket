# Sales & pipeline analytics (v1.2 CRM), shared by the staff dashboard and
# its CSV export. Computed entirely from this deployment's own deal + lead
# data — never transmitted anywhere.
#
# Two clocks are in play, deliberately:
#   * The open pipeline (#pipeline_by_stage, #by_owner open value) is a
#     CURRENT snapshot — "what's live right now", not date-filtered.
#   * Won/lost, created, and lead-conversion figures are WINDOWED by the
#     from..to range (wins/losses by closed_at, the same way ActivityReport
#     windows resolutions) so the period totals are stable.
class SalesReport
  attr_reader :from, :to

  def initialize(from:, to:)
    @from = from
    @to = to
  end

  def range
    from.beginning_of_day..to.end_of_day
  end

  # The open funnel: one row per stage holding open deals, ordered down the
  # pipeline. Terminal (won/lost) stages never appear — landing in one
  # derives the deal away from `open`, so this is exactly the active funnel.
  def pipeline_by_stage
    @pipeline_by_stage ||= begin
      counts = Deal.open_deals.group(:pipeline_stage_id).count
      values = Deal.open_deals.group(:pipeline_stage_id).sum(:value_cents)
      stages = PipelineStage.with_deleted.where(id: counts.keys).index_by(&:id)
      counts.keys.map do |sid|
        { stage: stages[sid], count: counts[sid], value_cents: values[sid] || 0 }
      end.sort_by { |row| [ row[:stage]&.pipeline_id || 0, row[:stage]&.position || 0 ] }
    end
  end

  # Probability-weighted open pipeline (a forecast): Σ value × stage odds.
  def weighted_pipeline_cents
    @weighted_pipeline_cents ||= pipeline_by_stage.sum do |row|
      (row[:value_cents] || 0) * (row[:stage]&.probability || 0) / 100.0
    end.round
  end

  def stats
    @stats ||= begin
      closed = Deal.with_deleted.where(closed_at: range)
      won_count  = closed.status_won.count
      lost_count = closed.status_lost.count
      decided    = won_count + lost_count
      created    = Deal.with_deleted.where(created_at: range)
      leads_created   = Lead.with_deleted.where(created_at: range).count
      leads_converted = Lead.with_deleted.where(converted_at: range).count
      {
        open_deals: Deal.open_deals.count,
        open_value_cents: Deal.open_deals.sum(:value_cents),
        weighted_value_cents: weighted_pipeline_cents,
        deals_created: created.count,
        deals_created_value_cents: created.sum(:value_cents),
        won_count: won_count,
        won_value_cents: closed.status_won.sum(:value_cents),
        lost_count: lost_count,
        lost_value_cents: closed.status_lost.sum(:value_cents),
        win_rate: decided.zero? ? nil : (won_count * 100.0 / decided).round(1),
        leads_created: leads_created,
        leads_converted: leads_converted,
        lead_conversion_rate: leads_created.zero? ? nil : (leads_converted * 100.0 / leads_created).round(1)
      }
    end
  end

  # Why deals were lost in the window — count + value per reason, most
  # common first. Only losses that recorded a reason are included.
  def loss_reasons
    @loss_reasons ||= begin
      lost = Deal.with_deleted.status_lost.where(closed_at: range).where.not(lost_reason: nil)
      counts = lost.group(:lost_reason).count
      values = lost.group(:lost_reason).sum(:value_cents)
      counts.map do |reason, count|
        key = reason.is_a?(Integer) ? Deal.lost_reasons.key(reason) : reason.to_s
        { reason: key, count: count, value_cents: values[reason] || 0 }
      end.sort_by { |row| -row[:count] }
    end
  end

  # Rep leaderboard: open pipeline value (snapshot) + won value (windowed)
  # per owner, biggest contributor first.
  def by_owner
    @by_owner ||= begin
      open_value = Deal.open_deals.where.not(owner_id: nil).group(:owner_id).sum(:value_cents)
      won_value  = Deal.with_deleted.status_won.where(closed_at: range)
                       .where.not(owner_id: nil).group(:owner_id).sum(:value_cents)
      owner_ids = (open_value.keys + won_value.keys).uniq
      owners = User.with_deleted.where(id: owner_ids).index_by(&:id)
      owner_ids.map do |oid|
        { owner: owners[oid], open_value_cents: open_value[oid] || 0, won_value_cents: won_value[oid] || 0 }
      end.sort_by { |row| -(row[:open_value_cents] + row[:won_value_cents]) }
    end
  end

  def to_csv
    require "csv"
    CSV.generate do |csv|
      csv << %w[section label count value_rupees from to]
      pipeline_by_stage.each do |row|
        csv << [ "pipeline_stage", csv_safe(row[:stage]&.name), row[:count], rupees(row[:value_cents]), from, to ]
      end
      csv << [ "summary", "won", stats[:won_count], rupees(stats[:won_value_cents]), from, to ]
      csv << [ "summary", "lost", stats[:lost_count], rupees(stats[:lost_value_cents]), from, to ]
      csv << [ "summary", "win_rate_pct", nil, stats[:win_rate], from, to ]
      loss_reasons.each do |row|
        csv << [ "loss_reason", row[:reason], row[:count], rupees(row[:value_cents]), from, to ]
      end
      by_owner.each do |row|
        csv << [ "owner", csv_safe(row[:owner]&.name), nil, rupees(row[:open_value_cents] + row[:won_value_cents]), from, to ]
      end
    end
  end

  private

  def rupees(cents)
    (cents || 0) / 100.0
  end

  # Spreadsheet formula-injection guard for text cells.
  def csv_safe(value)
    value.to_s.match?(/\A[=+\-@\t]/) ? "'#{value}" : value
  end
end
