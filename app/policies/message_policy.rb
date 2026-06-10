class MessagePolicy < ApplicationPolicy
  def create?
    Pundit.policy!(user, record.case).update?
  end

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
