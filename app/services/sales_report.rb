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
      counts = Deal.open_deals.group(:pipeline_stage_id, :currency).count
      values = Deal.open_deals.group(:pipeline_stage_id, :currency).sum(:value_cents)
      stages = PipelineStage.with_deleted.where(id: counts.keys.map(&:first)).index_by(&:id)
      counts.keys.map do |sid, currency|
        { stage: stages[sid], currency: currency, count: counts[[ sid, currency ]],
          value_cents: values[[ sid, currency ]] || 0 }
      end.sort_by do |row|
        [ row[:stage]&.pipeline_id || 0, row[:stage]&.position || 0, row[:currency] ]
      end
    end
  end

  # Probability-weighted open pipeline (a forecast): Σ value × stage odds,
  # kept separate by ISO currency. Adding INR and USD creates a plausible but
  # meaningless number, so reports never expose a mixed scalar.
  def weighted_pipeline_by_currency
    @weighted_pipeline_by_currency ||= pipeline_by_stage.each_with_object(Hash.new(0.0)) do |row, totals|
      totals[row[:currency]] += (row[:value_cents] || 0) * (row[:stage]&.probability || 0) / 100.0
    end.transform_values(&:round)
  end

  def stats
    @stats ||= begin
      closed = Deal.with_deleted.where(closed_at: range)
      won_count  = closed.status_won.count
      lost_count = closed.status_lost.count
      decided    = won_count + lost_count
      created    = Deal.with_deleted.where(created_at: range)
      lead_cohort = Lead.with_deleted.where(created_at: range)
      leads_created = lead_cohort.count
      leads_converted = lead_cohort.where(converted_at: range).count
      {
        open_deals: Deal.open_deals.count,
        open_values_by_currency: currency_sums(Deal.open_deals),
        weighted_values_by_currency: weighted_pipeline_by_currency,
        deals_created: created.count,
        deals_created_values_by_currency: currency_sums(created),
        won_count: won_count,
        won_values_by_currency: currency_sums(closed.status_won),
        lost_count: lost_count,
        lost_values_by_currency: currency_sums(closed.status_lost),
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
      counts = lost.group(:lost_reason, :currency).count
      values = lost.group(:lost_reason, :currency).sum(:value_cents)
      counts.map do |(reason, currency), count|
        key = reason.is_a?(Integer) ? Deal.lost_reasons.key(reason) : reason.to_s
        { reason: key, currency: currency, count: count,
          value_cents: values[[ reason, currency ]] || 0 }
      end.sort_by { |row| [ -row[:count], row[:reason], row[:currency] ] }
    end
  end

  def competitor_losses
    @competitor_losses ||= begin
      links = DealCompetitor.disposition_lost_to.joins(:deal)
                            .where(deals: { status: Deal.statuses.fetch("lost"), closed_at: range })
      counts = links.group(:competitor_id, "deals.currency").count
      values = links.group(:competitor_id, "deals.currency").sum("deals.value_cents")
      competitors = Competitor.with_deleted.where(id: counts.keys.map(&:first)).index_by(&:id)
      counts.map do |(competitor_id, currency), count|
        { competitor: competitors[competitor_id], currency: currency, count: count,
          value_cents: values[[ competitor_id, currency ]] || 0 }
      end.sort_by { |row| [ -row[:count], row[:competitor]&.name.to_s, row[:currency] ] }
    end
  end

  # Rep leaderboard: open pipeline value (snapshot) + won value (windowed)
  # per owner, biggest contributor first.
  def by_owner
    @by_owner ||= begin
      open_value = Deal.open_deals.where.not(owner_id: nil).group(:owner_id, :currency).sum(:value_cents)
      won_value  = Deal.with_deleted.status_won.where(closed_at: range)
                       .where.not(owner_id: nil).group(:owner_id, :currency).sum(:value_cents)
      keys = (open_value.keys + won_value.keys).uniq
      owner_ids = keys.map(&:first).uniq
      owners = User.with_deleted.where(id: owner_ids).index_by(&:id)
      keys.map do |oid, currency|
        { owner: owners[oid], currency: currency,
          open_value_cents: open_value[[ oid, currency ]] || 0,
          won_value_cents: won_value[[ oid, currency ]] || 0 }
      end.sort_by do |row|
        [ row[:currency], -(row[:open_value_cents] + row[:won_value_cents]), row[:owner]&.name.to_s ]
      end
    end
  end

  # Pipeline velocity over deals WON in the window: average days from creation
  # to close, plus average dwell per stage reconstructed from the audit log
  # (DealStageHistory). Audit-mined — fine at MVP volume; a daily rollup is the
  # path if won-deal counts grow large.
  def velocity
    @velocity ||= begin
      won = Deal.with_deleted.status_won.where(closed_at: range).to_a
      to_win = won.filter_map { |d| (d.closed_at - d.created_at).to_f if d.closed_at && d.created_at }

      dwell = Hash.new { |h, k| h[k] = [] }
      won.each do |deal|
        DealStageHistory.new(deal).segments.each { |seg| dwell[seg.stage_id] << seg.dwell_seconds }
      end
      stages = PipelineStage.with_deleted.where(id: dwell.keys.compact).index_by(&:id)

      {
        won_count: won.size,
        avg_days_to_win: to_win.any? ? (to_win.sum / to_win.size / 86_400.0).round(1) : nil,
        stage_dwell: dwell.map { |sid, secs|
          { stage: stages[sid], avg_days: (secs.sum / secs.size / 86_400.0).round(1) }
        }.sort_by { |row| -row[:avg_days] }
      }
    end
  end

  def to_csv
    require "csv"
    CSV.generate do |csv|
      csv << %w[section label count value currency from to]
      pipeline_by_stage.each do |row|
        csv << [ "pipeline_stage", csv_safe(row[:stage]&.name), row[:count],
                 decimal_value(row[:value_cents]), row[:currency], from, to ]
      end
      currency_rows(csv, "summary", "won", stats[:won_count], stats[:won_values_by_currency])
      currency_rows(csv, "summary", "lost", stats[:lost_count], stats[:lost_values_by_currency])
      csv << [ "summary", "win_rate_pct", nil, stats[:win_rate], nil, from, to ]
      loss_reasons.each do |row|
        csv << [ "loss_reason", row[:reason], row[:count], decimal_value(row[:value_cents]),
                 row[:currency], from, to ]
      end
      competitor_losses.each do |row|
        csv << [ "competitor_loss", csv_safe(row[:competitor]&.name), row[:count],
                 decimal_value(row[:value_cents]), row[:currency], from, to ]
      end
      by_owner.each do |row|
        csv << [ "owner", csv_safe(row[:owner]&.name), nil,
                 decimal_value(row[:open_value_cents] + row[:won_value_cents]),
                 row[:currency], from, to ]
      end
    end
  end

  def as_json
    {
      from: from, to: to, stats: stats,
      pipeline_by_stage: pipeline_by_stage.map { |row|
        row.except(:stage).merge(stage_id: row[:stage]&.id, stage: row[:stage]&.name)
      },
      loss_reasons: loss_reasons,
      competitor_losses: competitor_losses.map { |row|
        row.except(:competitor).merge(competitor_id: row[:competitor]&.id,
                                      competitor: row[:competitor]&.name)
      },
      velocity: velocity.merge(stage_dwell: velocity[:stage_dwell].map { |row|
        row.except(:stage).merge(stage_id: row[:stage]&.id, stage: row[:stage]&.name)
      })
    }
  end

  private

  def decimal_value(cents)
    (cents || 0) / 100.0
  end

  def currency_sums(scope)
    scope.group(:currency).sum(:value_cents).transform_keys(&:to_s).sort.to_h
  end

  def currency_rows(csv, section, label, count, totals)
    if totals.empty?
      csv << [ section, label, count, 0, nil, from, to ]
    else
      totals.each do |currency, cents|
        csv << [ section, label, count, decimal_value(cents), currency, from, to ]
      end
    end
  end

  # Spreadsheet formula-injection guard for text cells.
  def csv_safe(value)
    value.to_s.match?(/\A[=+\-@\t]/) ? "'#{value}" : value
  end
end
