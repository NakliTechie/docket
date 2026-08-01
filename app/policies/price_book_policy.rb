# Price books are CRM configuration — gated on pipeline:manage.
class PriceBookPolicy < ApplicationPolicy
  def index?   = permit?("pipeline:manage")
  def show?    = permit?("pipeline:manage")
  def create?  = permit?("pipeline:manage")
  def update?  = permit?("pipeline:manage")
  def destroy? = permit?("pipeline:manage")

  class Scope < Scope
    def resolve
      user&.can?("pipeline:manage") ? scope.all : scope.none
    end
  end
end
