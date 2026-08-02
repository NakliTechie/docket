class UserPolicy < ApplicationPolicy
  def index?   = permit?("user:manage")
  def show?    = permit?("user:manage") || record.id == user&.id
  def create?  = permit?("user:manage")
  def update?  = permit?("user:manage")
  def update_scope? = permit?("user:manage") && record.id != user.id
  def destroy? = permit?("user:manage") && record.id != user.id

  class Scope < Scope
    def resolve
      permit?("user:manage") ? scope.all : scope.none
    end
  end
end
