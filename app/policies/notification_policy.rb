class NotificationPolicy < ApplicationPolicy
  def index? = user.present?
  def read? = owned?
  def read_all? = user.present?

  class Scope < Scope
    def resolve
      user ? scope.where(user: user) : scope.none
    end
  end

  private

  def owned? = record.user_id == user&.id
end
