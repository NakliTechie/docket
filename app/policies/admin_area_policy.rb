# Headless policy for admin-only pages that aren't backed by a single
# record (audit status, activity & usage).
class AdminAreaPolicy < ApplicationPolicy
  def show? = admin?
  def index? = admin?
end
