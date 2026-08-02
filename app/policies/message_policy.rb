class MessagePolicy < ApplicationPolicy
  def create?
    Pundit.policy!(user, record.case).update?
  end

  class Scope < Scope
    def resolve
      return scope.none unless permit?("case:read")

      visible_cases = RecordVisibility.resolve(user, Case.all, access: :read)
      scope.where(case_id: visible_cases.select(:id))
    end
  end
end
