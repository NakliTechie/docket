# Headless policy for the read-only "Roles & permissions" matrix page. Whoever
# manages users may inspect what each role can do.
class RolePolicy < ApplicationPolicy
  def index? = permit?("user:manage")
end
