# A small, reversible set of string labels on a record (stored in a `labels`
# JSON column). The effect an applied Decision attaches — segment tags like
# "high_value_lead" / "stalled_deal" / "sla_at_risk". Reversible and audited
# (each change is a normal `update!`), which is what keeps acting on an
# :autonomous decision safe.
module Labelable
  extend ActiveSupport::Concern

  def labels
    Array(self[:labels])
  end

  def label?(value)
    labels.include?(value.to_s)
  end

  def add_label(value)
    value = value.to_s
    return self if value.blank? || label?(value)
    update!(labels: labels + [ value ])
    self
  end

  def remove_label(value)
    update!(labels: labels - [ value.to_s ])
    self
  end
end
