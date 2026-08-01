# The lead scorecard is CRM configuration — gated on pipeline:manage, the same
# authority that governs pipelines and lead routing.
class LeadScorecardPolicy < ApplicationPolicy
  def show?   = permit?("pipeline:manage")
  def update? = permit?("pipeline:manage")
end
