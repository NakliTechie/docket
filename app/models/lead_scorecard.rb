# PG5 — the tenant's editable lead-scoring scorecard (singleton). Signal weights
# + band thresholds + the warm-source list. Defaults reproduce the old
# hard-coded Decisioning::Rules::LeadScore (five 1-point signals, warm at 3).
class LeadScorecard < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  WEIGHTS = %w[weight_email weight_phone weight_company weight_warm_source weight_owned].freeze

  validates(*WEIGHTS, numericality: { only_integer: true, greater_than_or_equal_to: 0 })
  validates :warm_threshold, :hot_threshold, numericality: { only_integer: true, greater_than: 0 }
  validate :hot_at_or_above_warm

  # The tenant's scorecard, created with defaults on first use.
  def self.current
    first || create!
  end

  def warm_source?(source)
    warm_source_list.include?(source.to_s)
  end

  def warm_source_list
    warm_sources.to_s.split(",").map { |source| source.strip.downcase }.reject(&:blank?)
  end

  private

  def hot_at_or_above_warm
    return if warm_threshold.blank? || hot_threshold.blank?
    errors.add(:hot_threshold, "must be at or above the warm threshold") if hot_threshold < warm_threshold
  end
end
