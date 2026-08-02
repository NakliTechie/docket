# Headless policy for the decisioning controls (run / approve / reject).
# Approving a decision is an accountable action over the deployment's data, so
# it tracks the distinct decision-run authority.
class DecisionPolicy < ApplicationPolicy
  def index? = permit?("decision:run")
  def show? = index?
  def run? = permit?("decision:run")
  def approve? = run?
  def reject? = run?
end
