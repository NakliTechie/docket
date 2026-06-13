# Headless policy for the decisioning controls (run / approve / reject).
# Approving a decision is an accountable action over the deployment's data, so
# it tracks invocation:review — the same human-of-record tier as the effector
# approval queue.
class DecisionPolicy < ApplicationPolicy
  def run? = permit?("invocation:review")
  def approve? = run?
  def reject? = run?
end
