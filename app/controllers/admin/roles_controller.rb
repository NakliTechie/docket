module Admin
  # Read-only "Roles & permissions" matrix: renders Authz::ROLE_PERMISSIONS so
  # an operator or procurement/audit reviewer can see exactly what each role may
  # do. Pure render — the matrix is a constant, no model.
  class RolesController < ApplicationController
    def index
      authorize :roles, policy_class: RolePolicy
      @roles = Authz::ASSIGNABLE_ROLES
      @permissions = Authz::PERMISSIONS
    end
  end
end
