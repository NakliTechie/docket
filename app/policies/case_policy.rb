class CasePolicy < ApplicationPolicy
  # Single-tenant: all staff see all cases; mutation rights differ.
  def index? = staff?
  def show?  = staff?

  def create? = can_work?

  def update?
    admin? || supervisor? || (agent? && workable_by_agent?)
  end

  def transition? = update?
  def assign?     = update?

  def destroy? = admin? || supervisor?

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end

  private

  # Agents act on cases assigned to them, unassigned ones, or cases in
  # their queues.
  def workable_by_agent?
    record.assignee_id == user.id ||
      record.assignee_id.nil? ||
      user.queue_memberships.exists?(queue_id: record.queue_id)
  end
end
