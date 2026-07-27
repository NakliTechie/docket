# Where "/" goes. Cannot be a fixed destination any more: with modules
# toggleable per tenant, hard-wiring root to the case desk meant a CRM-only or
# work-only tenant landed on a 404 the moment they signed in — and the 404
# page's "back home" button pointed at the same 404.
#
# Sends the user to the first surface they actually have, most-owned first.
class HomeController < ApplicationController
  # Contacts is the floor: shared by every module, so it is always reachable.
  def index
    redirect_to landing_path
  end

  private

  def landing_path
    return cases_path    if feature?("service_desk") && policy(Case).index?
    return projects_path if feature?("work") && policy(Project).index?
    return leads_path    if feature?("crm") && policy(Lead).index?

    contacts_path
  end

  def skip_pundit? = true
end
