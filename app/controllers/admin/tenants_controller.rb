module Admin
  # The super_admin platform console: manage the fleet of tenants. In an isolated
  # deploy this shows the single primary tenant (informational); in a shared
  # deploy it provisions and suspends tenants. Tenant is not itself tenant-scoped,
  # so listing is naturally cross-tenant; per-tenant counts use with_tenant.
  class TenantsController < ApplicationController
    before_action :set_tenant, only: %i[suspend activate]

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

    private

    def set_tenant
      @tenant = Tenant.find(params[:id])
    end

    def tenant_params
      params.require(:tenant).permit(:name, :subdomain, :admin_email)
    end
  end
end
