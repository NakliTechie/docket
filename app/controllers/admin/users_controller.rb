module Admin
  class UsersController < ApplicationController
    before_action :set_user, only: %i[show edit update destroy activate deactivate]

    def index
      authorize User
      @pagy, @users = pagy(policy_scope(User).order(:name))
    end

    def show
      authorize @user
      @recent_actions = AuditEntry.where(actor: @user).order(id: :desc).limit(20)
    end

    def new
      @user = User.new
      authorize @user
    end

    def create
      @user = User.new(user_params)
      authorize @user
      if @user.save
        redirect_to admin_users_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @user
    end

    def update
      authorize @user
      attrs = user_params
      attrs = attrs.except(:password) if attrs[:password].blank?
      if @user.update(attrs)
        redirect_to admin_users_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @user
      @user.deactivate!
      @user.destroy
      redirect_to admin_users_path, notice: t(".deleted"), status: :see_other
    end

    def activate
      authorize @user, :update?
      @user.update!(active: true)
      redirect_to admin_users_path, notice: t(".activated")
    end

    def deactivate
      authorize @user, :update?
      if @user == Current.user
        redirect_to admin_users_path, alert: t(".cannot_deactivate_self"), status: :see_other
      else
        @user.deactivate!
        redirect_to admin_users_path, notice: t(".deactivated")
      end
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:name, :email_address, :password, :role, :locale, queue_ids: [])
    end
  end
end
