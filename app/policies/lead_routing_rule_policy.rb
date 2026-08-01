# Lead-routing rules are CRM configuration — the whole surface (including reading
# the list) is gated on pipeline:manage, the same authority that governs
# pipelines and other CRM structure (held by client_admin + super_admin).
class LeadRoutingRulePolicy < ApplicationPolicy
  def index?   = permit?("pipeline:manage")
  def show?    = permit?("pipeline:manage")
  def create?  = permit?("pipeline:manage")
  def update?  = permit?("pipeline:manage")
  def destroy? = permit?("pipeline:manage")
  def move?    = permit?("pipeline:manage")

  class Scope < Scope
    def resolve
      user&.can?("pipeline:manage") ? scope.all : scope.none
    end
  end
end
