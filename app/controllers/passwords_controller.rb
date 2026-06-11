class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 10, within: 3.minutes, only: :create,
             with: -> { redirect_to new_password_path, alert: t("sessions.rate_limited") }

  def new
  end

  def create
    if user = User.active.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: t(".sent")
  end

  def edit
  end

  def update
    if params[:password].blank?
      # has_secure_password skips presence on update, so a blank password
      # would "succeed" without changing anything — reject it explicitly.
      return redirect_to edit_password_path(params[:token]), alert: t(".mismatch")
    end

    if @user.update(params.permit(:password, :password_confirmation))
      @user.sessions.destroy_all
      AuditEntry.append!(action: "user.password_reset", auditable: @user, actor: @user)
      redirect_to new_session_path, notice: t(".reset")
    else
      redirect_to edit_password_path(params[:token]), alert: t(".mismatch")
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
      # A valid signature whose user was since soft-deleted resolves to no
      # record (default scope) → RecordNotFound; treat it like a bad token
      # rather than 500ing.
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_password_path, alert: t("passwords.invalid_token")
    end
end
