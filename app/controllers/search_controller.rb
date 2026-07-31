class SearchController < ApplicationController
  RESULT_LIMIT = 10

  def index
    @query = params[:q].to_s.strip.first(200)
    @results = {}
    contacts_scope = policy_scope(Contact)
    return if @query.blank?

    add_results(:cases, feature?("service_desk") && policy(Case).index?,
                -> { policy_scope(Case).canonical.search(@query).order(updated_at: :desc) })
    add_results(:contacts, policy(Contact).index?,
                -> { contacts_scope.search(@query).order(:name) })
    add_results(:leads, feature?("crm") && policy(Lead).index?,
                -> { policy_scope(Lead).search(@query).order(updated_at: :desc) })
    add_results(:deals, feature?("crm") && policy(Deal).index?,
                -> { policy_scope(Deal).search(@query).order(updated_at: :desc) })
    add_results(:work_items, feature?("work") && policy(WorkItem).index?,
                -> { policy_scope(WorkItem).includes(:project).search(@query).order("work_items.updated_at DESC") })
  end

  private

  def add_results(key, allowed, relation)
    return unless allowed

    @results[key] = relation.call.limit(RESULT_LIMIT).to_a
  end
end
