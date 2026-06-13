module Admin
  class ApiTokensController < ApplicationController
    def index
      authorize :api_tokens, policy_class: PlatformAreaPolicy
      @api_tokens = ApiToken.includes(:user).order(id: :desc)
      @api_token = ApiToken.new
    end

    def create
      authorize :api_tokens, policy_class: PlatformAreaPolicy
      @api_token = ApiToken.new(token_params)
      if @api_token.save
        flash[:api_token_raw] = @api_token.raw_token
        redirect_to admin_api_tokens_path, notice: t(".created")
      else
        redirect_to admin_api_tokens_path, alert: @api_token.errors.full_messages.to_sentence
      end
    end

    def destroy
      authorize :api_tokens, policy_class: PlatformAreaPolicy
      ApiToken.find(params[:id]).revoke!
      redirect_to admin_api_tokens_path, notice: t(".revoked"), status: :see_other
    end

    private

    def token_params
      params.require(:api_token).permit(:user_id, :name)
    end
  end
end
