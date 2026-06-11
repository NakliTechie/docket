module Admin
  # Admin surface for the connector framework: configure an integration,
  # map its fields, schedule it, run it on demand, and read its sync log.
  class ConnectorsController < ApplicationController
    before_action :set_connector, only: %i[show edit update destroy sync pause resume]

    def index
      authorize Connector
      @connectors = policy_scope(Connector).order(:name)
      @descriptors = Connectors::Registry.descriptors
    end

    def new
      @connector = Connector.new(provider: params[:provider], target: "contacts")
      authorize @connector
      @descriptor = Connectors::Registry.descriptor(@connector.provider)
    end

    def create
      @connector = Connector.new(connector_params)
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

    private

    def set_connector
      @connector = Connector.find(params[:id])
    end

    def connector_params
      params.require(:connector).permit(:name, :provider, :target, :schedule_interval_minutes,
                                        config: {}, field_mapping: {})
    end

    # Secrets only change when a new value is typed — a blank field keeps
    # the stored credential (so editing a connector doesn't wipe its key).
    def assign_credentials
      api_key = params.dig(:connector, :credentials, :api_key)
      @connector.credentials_hash = { "api_key" => api_key } if api_key.present?
    end
  end
end
