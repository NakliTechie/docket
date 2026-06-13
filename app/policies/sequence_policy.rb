class SequencePolicy < ApplicationPolicy
  # Sequence definitions are CRM-admin config; enrolling targets is operational
  # work the sales/service desk can do.
  def index?   = permit?("pipeline:read")
  def show?    = permit?("pipeline:read")
  def create?  = permit?("pipeline:manage")
  def update?  = permit?("pipeline:manage")
  def destroy? = permit?("pipeline:manage")
  def enroll?  = permit?("sequence:enroll")

  class Scope < Scope
    def resolve
      user.present? ? scope.all : scope.none
    end
  end
end
