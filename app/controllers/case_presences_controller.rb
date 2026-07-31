class CasePresencesController < ApplicationController
  require_feature "service_desk"

  def create
    kase = policy_scope(Case).find(params[:case_id])
    presence = CasePresence.new(case: kase, user: Current.user, last_seen_at: Time.current)
    authorize presence
    CasePresence.touch_for!(kase, Current.user)
    render json: { agents: other_agents(kase) }
  end

  def destroy
    kase = policy_scope(Case).find(params[:case_id])
    presence = CasePresence.find_by(case: kase, user: Current.user)
    authorize(presence || CasePresence.new(case: kase, user: Current.user))
    presence&.destroy
    head :no_content
  end

  private

  def other_agents(kase)
    CasePresence.active.where(case: kase).where.not(user: Current.user)
                .includes(:user).map { |presence| presence.user.name }
  end
end
