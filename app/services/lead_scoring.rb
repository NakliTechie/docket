# PG5 — computes and persists a lead's score + band from the tenant's editable
# LeadScorecard. Single source of truth for lead scoring: the after_save
# recompute, the admin re-score, and Decisioning::Rules::LeadScore all call here.
module LeadScoring
  module_function

  # The signals and which scorecard weight each draws from.
  def score_for(lead, scorecard = LeadScorecard.current)
    score = 0
    score += scorecard.weight_email if lead.email.present?
    score += scorecard.weight_phone if lead.phone.present?
    score += scorecard.weight_company if lead.company_name.present?
    score += scorecard.weight_warm_source if scorecard.warm_source?(lead.source)
    score += scorecard.weight_owned if lead.owner_id.present?
    score
  end

  def matched_signals(lead, scorecard = LeadScorecard.current)
    signals = []
    signals << "email" if lead.email.present?
    signals << "phone" if lead.phone.present?
    signals << "company" if lead.company_name.present?
    signals << "warm_source" if scorecard.warm_source?(lead.source)
    signals << "owned" if lead.owner_id.present?
    signals
  end

  def band_for(score, scorecard = LeadScorecard.current)
    if score >= scorecard.hot_threshold then :hot
    elsif score >= scorecard.warm_threshold then :warm
    else :cold
    end
  end

  # Persist the score + band without re-running Lead callbacks (derived data,
  # not a decision of record — keep it off the audit chain and out of recompute
  # recursion). Skips the write when nothing changed (band is compared as the
  # string enum value, not the integer, so the guard actually holds).
  def apply!(lead, scorecard = LeadScorecard.current)
    score = score_for(lead, scorecard)
    band = band_for(score, scorecard).to_s
    if lead.score != score || lead.score_band != band
      lead.update_columns(score: score, score_band: Lead.score_bands.fetch(band))
    end
    score
  end

  # Re-score every lead against the (possibly just-edited) scorecard, so the
  # persisted scores + the leads index/sort stay consistent with the config.
  def rescore_all!(scorecard = LeadScorecard.current)
    Lead.find_each { |lead| apply!(lead, scorecard) }
  end
end
