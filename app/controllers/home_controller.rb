# Where "/" goes. Cannot be a fixed destination any more: with modules
# toggleable per tenant, hard-wiring root to the case desk meant a CRM-only or
# work-only tenant landed on a 404 the moment they signed in — and the 404
# page's "back home" button pointed at the same 404.
#
# Sends the user to the first surface they actually have, most-owned first.
class HomeController < ApplicationController
  # Contacts is the floor: shared by every module, so it is always reachable.
  def index
    setup = SetupProgress.new(actor: Current.user, base_url: request.base_url)
    if setup_access? && setup.needs_attention?
      return redirect_to setup_path
    end

    redirect_to landing_path
  end

  private

  def landing_path
    role_destination = role_landing_path
    return role_destination if role_destination

    return cases_path    if feature?("service_desk") && policy(Case).index?
    return projects_path if feature?("work") && policy(Project).index?
    return leads_path    if feature?("crm") && policy(Lead).index?

    contacts_path
  end

  def role_landing_path
    case Current.user.role
    when "sales"
      leads_path if feature?("crm") && policy(Lead).index?
    when "finance", "client_admin", "super_admin"
      dashboard_path if DashboardPolicy.new(Current.user, :dashboard).index?
    when "technical"
      admin_connectors_path if feature?("connectors") && policy(Connector).index?
    end
  end

  def setup_access?
    PlatformAreaPolicy.new(Current.user, :settings).show?
  end

  def skip_pundit? = true
end
