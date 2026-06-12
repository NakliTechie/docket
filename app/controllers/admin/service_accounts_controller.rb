module Admin
  class ServiceAccountsController < ApplicationController
    before_action :set_account, only: %i[edit update destroy rotate_secret]

    def index
      authorize :service_accounts, policy_class: AdminAreaPolicy
      @service_accounts = ServiceAccount.order(:name)
    end

    def new
      authorize :service_accounts, policy_class: AdminAreaPolicy
      @service_account = ServiceAccount.new
    end

    def create
      authorize :service_accounts, policy_class: AdminAreaPolicy
      @service_account = ServiceAccount.new(account_params)
      if @service_account.save
        flash[:client_secret] = @service_account.raw_client_secret
        redirect_to admin_service_accounts_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize :service_accounts, policy_class: AdminAreaPolicy
    end

    def update
      authorize :service_accounts, policy_class: AdminAreaPolicy
      if @service_account.update(account_params)
        @service_account.deactivate! unless @service_account.active
        redirect_to admin_service_accounts_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize :service_accounts, policy_class: AdminAreaPolicy
      @service_account.deactivate!
      @service_account.destroy
      redirect_to admin_service_accounts_path, notice: t(".deleted"), status: :see_other
    end

    def rotate_secret
      authorize :service_accounts, policy_class: AdminAreaPolicy
      flash[:client_secret] = @service_account.rotate_secret!
      redirect_to admin_service_accounts_path, notice: t(".rotated")
    end

    private

    def set_account
      @service_account = ServiceAccount.find(params[:id])
    end

    def account_params
      permitted = params.require(:service_account).permit(:name, :description, :active,
                                                          :action_budget, :action_budget_window_minutes, scopes: [])
      # Drop the empty-string companion (and any blanks) so an all-unchecked
      # submission becomes [] and trips the "at least one scope" validation.
      permitted[:scopes] = Array(permitted[:scopes]).reject(&:blank?) if permitted.key?(:scopes)
      permitted
    end
  end
end
