class ReferenceDocPolicy < ApplicationPolicy
  def index?   = permit?("reference_doc:manage")
  def show?    = permit?("reference_doc:manage")
  def create?  = permit?("reference_doc:manage")
  def update?  = permit?("reference_doc:manage")
  def destroy? = permit?("reference_doc:manage")

  class Scope < Scope
    def resolve
      permit?("reference_doc:manage") ? scope.all : scope.none
    end
  end
end
