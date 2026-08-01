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
  # recursion).
  def apply!(lead, scorecard = LeadScorecard.current)
    score = score_for(lead, scorecard)
    band = Lead.score_bands.fetch(band_for(score, scorecard).to_s)
    lead.update_columns(score: score, score_band: band) if lead.score != score || lead.score_band != band
    score
  end
end
