module Admin
  # The super_admin platform console: manage the fleet of tenants. In an isolated
  # deploy this shows the single primary tenant (informational); in a shared
  # deploy it provisions and suspends tenants. Tenant is not itself tenant-scoped,
  # so listing is naturally cross-tenant; per-tenant counts use with_tenant.
  class TenantsController < ApplicationController
    before_action :set_tenant, only: %i[suspend activate entitlements update_entitlements]

    def index
      authorize Tenant
      @tenants = Tenant.order(:name)
      @case_counts = @tenants.to_h { |t| [ t.id, ActsAsTenant.with_tenant(t) { Case.count } ] }
    end

    def new
      authorize Tenant
      @tenant = Tenant.new
    end

    def create
      authorize Tenant
      result = Tenants::Provisioner.call(
        name: tenant_params[:name],
        subdomain: tenant_params[:subdomain],
        admin_email: tenant_params[:admin_email].presence
      )
      # The one-time admin password is shown once, like the break-glass seed.
      flash[:tenant_admin_password] = result.admin_password if result.admin_password
      redirect_to admin_tenants_path, notice: t(".created", name: result.tenant.name)
    rescue ActiveRecord::RecordInvalid => e
      @tenant = Tenant.new(name: tenant_params[:name], subdomain: tenant_params[:subdomain])
      flash.now[:alert] = e.record.errors.full_messages.to_sentence.presence || e.message
      render :new, status: :unprocessable_entity
    end

    def suspend
      authorize @tenant
      if @tenant.slug == Tenant::PRIMARY_SLUG
        redirect_to admin_tenants_path, alert: t(".cannot_suspend_primary") and return
      end
      @tenant.suspended!
      redirect_to admin_tenants_path, notice: t(".suspended", name: @tenant.name)
    end

    def activate
      authorize @tenant
      @tenant.active!
      redirect_to admin_tenants_path, notice: t(".activated", name: @tenant.name)
    end

    # Which modules this tenant has bought. In a DEDICATED deploy this is the
    # operator's own switchboard on the primary tenant — same screen, same
    # mechanism, so there is no second code path to keep correct.
    def entitlements
      authorize @tenant, :update_entitlements?
      @grouped = Features.grouped
    end

    def update_entitlements
      authorize @tenant, :update_entitlements?

      if (preset = params[:preset].presence)
        @tenant.apply_preset!(preset)
        redirect_to entitlements_admin_tenant_path(@tenant),
                    notice: t(".preset_applied", preset: preset) and return
      end

      # Unchecked boxes don't post, so absence means OFF — the submitted list is
      # the whole truth for this form.
      enabled = Array(params[:features]).map(&:to_s)
      @tenant.update!(entitlements: Features::KEYS.index_with { |key| enabled.include?(key) }
                                                  .reject { |_, on| on })
      redirect_to entitlements_admin_tenant_path(@tenant), notice: t(".updated", name: @tenant.name)
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to entitlements_admin_tenant_path(@tenant), alert: e.message
    end

    private

    def set_tenant
      @tenant = Tenant.find(params[:id])
    end

    def tenant_params
      params.require(:tenant).permit(:name, :subdomain, :admin_email)
    end
  end
end
