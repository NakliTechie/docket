# Escalation rules are case-desk configuration — the whole surface (including
# reading the list) is gated on the SLA-management authority.
class EscalationRulePolicy < ApplicationPolicy
  def index?   = permit?("sla:manage")
  def show?    = permit?("sla:manage")
  def create?  = permit?("sla:manage")
  def update?  = permit?("sla:manage")
  def destroy? = permit?("sla:manage")
  def move?    = permit?("sla:manage")

  class Scope < Scope
    def resolve
      user&.can?("sla:manage") ? scope.all : scope.none
    end
  end
end
