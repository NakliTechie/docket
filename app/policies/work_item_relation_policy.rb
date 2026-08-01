class WorkItemRelationPolicy < ApplicationPolicy
  def create? = writable?(record.source) && writable?(record.target)
  def destroy? = create?

  private

  def writable?(item)
    item && WorkItemPolicy.new(user, item).update?
  end
end
