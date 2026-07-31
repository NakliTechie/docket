class SavedViewPolicy < ApplicationPolicy
  def create? = user.present? && record.user_id == user.id
  def destroy? = user.present? && record.user_id == user.id
end
