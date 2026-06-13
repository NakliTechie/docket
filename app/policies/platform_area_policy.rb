# Headless policy for the platform-plumbing admin areas not backed by a single
# record: settings, service accounts, API tokens, webhook endpoints. Each
# resource is gated on its own manage-permission (passed as the authorize
# subject symbol) rather than a blanket admin check — all are super_admin-tier
# except webhooks, which technical also holds. An unrecognised subject
# fail-closes (permit?(nil) → denied).
class PlatformAreaPolicy < ApplicationPolicy
  PERMISSION = {
    settings: "settings:manage",
    service_accounts: "service_account:manage",
    api_tokens: "api_token:manage",
    webhooks: "webhook:manage"
  }.freeze

  def index?   = permitted?
  def show?    = permitted?
  def new?     = permitted?
  def create?  = permitted?
  def edit?    = permitted?
  def update?  = permitted?
  def destroy? = permitted?

  # Custom member actions used by the admin controllers.
  def rotate_secret? = permitted?
  def deliveries?    = permitted?

  private

  def permitted?
    permit?(PERMISSION[record])
  end
end
