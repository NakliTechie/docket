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
      @user = User.new(user_params.except(:record_read_scope, :record_write_scope,
                                           :team_ids, :scoped_account_ids))
      authorize @user
      role_valid = assign_requested_role(@user)
      scope_valid = assign_requested_record_scopes(@user)
      if role_valid && scope_valid && save_with_scope_memberships(@user)
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
      if scope_assignment_requested? && !policy(@user).update_scope?
        @user.errors.add(:base, :scope_self_managed)
        return render :edit, status: :unprocessable_entity
      end
      attrs = user_params
      attrs = attrs.except(:password) if attrs[:password].blank?
      attrs = attrs.except(:record_read_scope, :record_write_scope,
                           :team_ids, :scoped_account_ids)
      @user.assign_attributes(attrs)
      role_valid = assign_requested_role(@user)
      scope_valid = assign_requested_record_scopes(@user)
      if role_valid && scope_valid && save_with_scope_memberships(@user)
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
      params.require(:user).permit(:name, :email_address, :password, :locale,
                                   :email_signature, :record_read_scope, :record_write_scope,
                                   queue_ids: [], team_ids: [], scoped_account_ids: [])
    end

    def assign_requested_role(user)
      return true unless params.require(:user).key?(:role)

      role = params.require(:user)[:role]
      if role.is_a?(String) && User.roles.key?(role)
        user.role = role
        true
      else
        user.errors.add(:role, :inclusion)
        false
      end
    end

    def assign_requested_record_scopes(user)
      raw = params.require(:user)
      %i[record_read_scope record_write_scope].all? do |attribute|
        next true unless raw.key?(attribute)

        value = raw[attribute]
        allowed = User.public_send(attribute.to_s.pluralize)
        if value.is_a?(String) && allowed.key?(value)
          user.public_send("#{attribute}=", value)
          true
        else
          user.errors.add(attribute, :inclusion)
          false
        end
      end
    end

    def scope_assignment_requested?
      raw = params.require(:user)
      %i[record_read_scope record_write_scope team_ids scoped_account_ids].any? { |key| raw.key?(key) }
    end

    def save_with_scope_memberships(user)
      saved = false
      User.transaction do
        saved = user.save
        if saved
          raw = params.require(:user)
          user.team_ids = Team.where(id: raw[:team_ids]).ids if raw.key?(:team_ids)
          if raw.key?(:scoped_account_ids)
            user.scoped_account_ids = Organisation.where(id: raw[:scoped_account_ids]).ids
          end
        end
      end
      saved
    end
  end
end
