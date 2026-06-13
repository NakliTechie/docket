# Headless policy for the decisioning controls (run / approve / reject). Same
# authority as the dashboard that surfaces them — admin + supervisor — since
# approving a decision is an accountable action over the deployment's data.
class DecisionPolicy < ApplicationPolicy
  def run? = admin? || supervisor?
  def approve? = run?
  def reject? = run?
end
