class CasePresencePolicy < ApplicationPolicy
  def create? = CasePolicy.new(user, record.case).show?
  def destroy? = record.user_id == user&.id
end
