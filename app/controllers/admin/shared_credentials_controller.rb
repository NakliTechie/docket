module Admin
  # Admin panel for app-level shared credentials/licences reused across
  # connectors. Secrets are write-only (never echoed); a blank field on edit
  # keeps the stored value.
  class SharedCredentialsController < ApplicationController
    before_action :set_credential, only: %i[edit update destroy]

    def index
      authorize SharedCredential
      @shared_credentials = policy_scope(SharedCredential).ordered
    end

    def new
      @shared_credential = SharedCredential.new
      authorize @shared_credential
    end

    def create
      @shared_credential = SharedCredential.new(credential_params)
      authorize @shared_credential
      assign_secrets
      if @shared_credential.save
        redirect_to admin_shared_credentials_path, notice: t(".created")
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @shared_credential
    end

    def update
      authorize @shared_credential
      @shared_credential.assign_attributes(credential_params)
      assign_secrets
      if @shared_credential.save
        redirect_to admin_shared_credentials_path, notice: t(".updated")
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @shared_credential
      @shared_credential.destroy
      redirect_to admin_shared_credentials_path, notice: t(".deleted"), status: :see_other
    end

    private

    def set_credential
      @shared_credential = SharedCredential.find(params[:id])
    end

    def credential_params
      params.require(:shared_credential).permit(:name, :label, :description)
    end

    # Merge any typed secret fields into the blob; blank = leave unchanged.
    def assign_secrets
      current = @shared_credential.secrets_hash
      SharedCredential::COMMON_FIELDS.each do |field|
        value = params.dig(:shared_credential, :secrets, field)
        current[field] = value if value.present?
      end
      @shared_credential.secrets_hash = current
    end
  end
end
