class DealLineItemPolicy < ApplicationPolicy
  def create?  = writable_deal?
  def update?  = writable_deal?
  def destroy? = writable_deal?

  class Scope < Scope
    def resolve
      return scope.none unless permit?("deal:read")

      visible_deals = RecordVisibility.resolve(user, Deal.all, access: :read)
      scope.where(deal_id: visible_deals.select(:id))
    end
  end

  private

  def writable_deal?
    permit?("deal:write") &&
      (record.is_a?(Class) || record.deal.nil? || DealPolicy.new(user, record.deal).update?)
  end
end
