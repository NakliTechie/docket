# Controller-side entitlement enforcement.
#
#   class LeadsController < ApplicationController
#     require_feature "crm"
#
# HTML gets 404, not 403, and that is deliberate: a tenant without the CRM module
# should not be told a CRM exists behind a wall — for them the surface simply
# isn't part of the product. (The API answers 403 `feature_disabled` instead,
# because an integrator holding a valid token needs a diagnosable reason.)
#
# This is the request-level seam. The others: `User#can?` (Authz intersection),
# view helpers (`feature?` — nav, palette, dashboard panes), the job fan-out
# (`each_tenant_with_feature`), and the MCP/OpenAPI catalog filter. The guard
# here is the backstop that holds even when a URL is hit directly — but it is
# only a backstop: anything that runs OUTSIDE a request (jobs, mailboxes) has
# to gate itself, which is why the fan-out helper exists.
module FeatureGating
  extend ActiveSupport::Concern

  class_methods do
    def require_feature(key, **options)
      before_action(**options) { ensure_feature!(key) }
    end
  end

  included do
    helper_method :feature? if respond_to?(:helper_method)
  end

  private

  def feature?(key)
    Features.enabled?(key)
  end

  def ensure_feature!(key)
    return if Features.enabled?(key)

    feature_disabled(key)
  end

  # Overridden in the API base controller.
  def feature_disabled(_key)
    respond_to do |format|
      format.html { render "errors/not_found", status: :not_found }
      format.json { render json: { error: "feature_disabled" }, status: :forbidden }
      format.any  { head :not_found }
    end
  end
end
