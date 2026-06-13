class CasePolicy < ApplicationPolicy
  # Single-tenant: all staff see all cases; mutation rights differ.
  def index? = permit?("case:read")
  def show?  = permit?("case:read")

  def create? = permit?("case:write")

  # Full writers (the case-admin tiers, which also hold case:delete) may edit
  # any case; restricted writers (the service desk) only their own, unassigned,
  # or in-queue cases.
  def update?
    permit?("case:write") && (full_case_write? || workable_by_agent?)
  end

  def transition? = update?
  def assign?     = update?

  def destroy? = permit?("case:delete")

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end

  private

  # The unrestricted-write marker: the case-admin tiers hold case:delete; the
  # service-desk tier does not and so falls through to workable_by_agent?.
  def full_case_write? = permit?("case:delete")

  # Restricted writers act on cases assigned to them, unassigned ones, or cases
  # in their queues.
  def workable_by_agent?
    record.assignee_id == user.id ||
      record.assignee_id.nil? ||
      user.queue_memberships.exists?(queue_id: record.queue_id)
  end
end
