# Headless policy for the decisioning controls (run / approve / reject).
# Approving a decision is an accountable action over the deployment's data, so
# it tracks the distinct decision-run authority.
class DecisionPolicy < ApplicationPolicy
  def index? = permit?("decision:run")
  def show? = index? && record_in_scope?(:read)
  def run? = permit?("decision:run")
  def approve? = run? && record_in_scope?(:write)
  def reject? = approve?

  class Scope < Scope
    def resolve
      permit?("decision:run") ? record_scope : scope.none
    end
  end
end
