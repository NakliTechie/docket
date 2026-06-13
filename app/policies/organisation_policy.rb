class OrganisationPolicy < ApplicationPolicy
  # Organisations ride with contacts.
  def index?   = permit?("contact:read")
  def show?    = permit?("contact:read")
  def create?  = permit?("contact:write")
  def update?  = permit?("contact:write")
  def destroy? = permit?("contact:delete")

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
