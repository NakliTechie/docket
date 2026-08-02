module Admin
  class TeamsController < ApplicationController
    before_action :set_team, only: %i[edit update destroy]

    def index
      authorize Team
      @teams = policy_scope(Team).includes(:members).order(:name)
    end

    def new
      @team = Team.new
      authorize @team
    end

    def create
      @team = Team.new(team_params)
      authorize @team
      if self_membership_change?(@team)
        @team.errors.add(:base, :scope_self_managed)
        render :new, status: :unprocessable_entity
      elsif @team.save
        redirect_to admin_teams_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @team
    end

    def update
      authorize @team
      if self_membership_change?(@team)
        @team.assign_attributes(team_params.except(:member_ids))
        @team.errors.add(:base, :scope_self_managed)
        render :edit, status: :unprocessable_entity
      elsif @team.update(team_params)
        redirect_to admin_teams_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @team
      if @team.members.exists?(Current.user.id)
        @team.errors.add(:base, :scope_self_managed)
        render :edit, status: :unprocessable_entity
      else
        @team.destroy
        redirect_to admin_teams_path, notice: t(".deleted"), status: :see_other
      end
    end

    private

    def set_team
      @team = Team.find(params[:id])
    end

    def team_params
      params.require(:team).permit(:name, :description, member_ids: [])
    end

    # A manager may not expand their own record visibility by adding peers to
    # a team they belong to, joining a new team, or removing that relationship.
    def self_membership_change?(team)
      return false unless params.require(:team).key?(:member_ids)

      requested_ids = Array(params.require(:team)[:member_ids]).filter_map { |id| Integer(id, exception: false) }
      team.members.exists?(Current.user.id) || requested_ids.include?(Current.user.id)
    end
  end
end
