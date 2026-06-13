module Admin
  # Admin surface for the connector framework: configure an integration,
  # map its fields, schedule it, run it on demand, and read its sync log.
  class ConnectorsController < ApplicationController
    before_action :set_connector, only: %i[show edit update destroy sync pause resume activate]

    def index
      authorize Connector
      @connectors = policy_scope(Connector).order(:name)
      @descriptors = Connectors::Registry.descriptors
    end

    def new
      @connector = Connector.new(provider: params[:provider],
                                 target: params[:target].presence_in(Connector::TARGETS) || "contacts")
      authorize @connector
      @descriptor = Connectors::Registry.descriptor(@connector.provider)
    end

    def create
      @connector = Connector.new(connector_params)
      @connector.status = :draft # configure-later: wired, activate when ready
      authorize @connector
      assign_credentials
      if @connector.save
        redirect_to admin_connector_path(@connector), notice: t(".created")
      else
        @descriptor = Connectors::Registry.descriptor(@connector.provider)
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize @connector
      @runs = @connector.connector_runs.recent_first.limit(20)
      @invocations = @connector.invocations.includes(:requested_by).recent_first.limit(20)
    end

    def edit
      authorize @connector
      @descriptor = @connector.provider_descriptor
    end

    def update
      authorize @connector
      @connector.assign_attributes(connector_params)
      assign_credentials
      if @connector.save
        redirect_to admin_connector_path(@connector), notice: t(".updated")
      else
        @descriptor = @connector.provider_descriptor
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @connector
      @connector.destroy
      redirect_to admin_connectors_path, notice: t(".deleted"), status: :see_other
    end

    def sync
      authorize @connector, :update?
      ConnectorSyncJob.perform_later(@connector.id, trigger: "manual")
      redirect_to admin_connector_path(@connector), notice: t(".sync_started")
    end

    def pause
      authorize @connector, :update?
      @connector.update!(status: :paused)
      redirect_to admin_connector_path(@connector), notice: t(".paused")
    end

    def resume
      authorize @connector, :update?
      @connector.update!(status: :active)
      redirect_to admin_connector_path(@connector), notice: t(".resumed")
    end

    # Configure-later: take a draft connector live, once its required
    # credentials are present.
    def activate
      authorize @connector, :update?
      if @connector.configured?
        @connector.update!(status: :active)
        redirect_to admin_connector_path(@connector), notice: t(".activated")
      else
        redirect_to admin_connector_path(@connector), alert: t(".not_configured")
      end
    end

    private

    def set_connector
      @connector = Connector.find(params[:id])
    end

    def connector_params
      # NOTE (S5): effector exposure — enabled_actions / auto_approve_actions /
      # action_budget(_window_minutes) — is intentionally NOT settable here. It's
      # managed via console/seed only (a deliberate, audited step before an agent
      # may invoke a connector); the model's enabled_actions_are_known /
      # auto_approve_within_enabled validations guard that path, not this form.
      params.require(:connector).permit(:name, :provider, :target, :schedule_interval_minutes,
                                        :shared_credential_id, config: {}, field_mapping: {})
    end

    # Secrets only change when a new value is typed — a blank field keeps the
    # stored value (so editing a connector doesn't wipe its keys). Each
    # provider declares which secret fields it stores (descriptor.secret_fields).
    def assign_credentials
      descriptor = @connector.provider_descriptor
      return unless descriptor

      current = @connector.credentials_hash
      descriptor.secret_fields.each do |field|
        value = params.dig(:connector, :credentials, field)
        current[field] = value if value.present?
      end
      @connector.credentials_hash = current
    end
  end
end
