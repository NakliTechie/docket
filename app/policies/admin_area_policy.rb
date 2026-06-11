# Headless policy for admin-only areas not backed by a single record
# (audit status, activity & usage, settings, api tokens, service
# accounts, webhook endpoints). Every action on these surfaces is
# admin-only — including the mutation and custom member actions
# (rotate_secret, deliveries), whose query methods Pundit derives from
# the action name. Without these, Pundit falls through to
# ApplicationPolicy's default-deny `false` (403) or raises NoMethodError
# for the undefined predicates (500), making the whole admin UI for
# these resources unusable.
class AdminAreaPolicy < ApplicationPolicy
  def index?   = admin?
  def show?    = admin?
  def new?     = admin?
  def create?  = admin?
  def edit?    = admin?
  def update?  = admin?
  def destroy? = admin?

  # Custom member actions used by the admin controllers.
  def rotate_secret? = admin?
  def deliveries?    = admin?
end
