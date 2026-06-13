# Single authorisation layer (handoff §2): every controller action and
# API endpoint authorises through these policies. Default is deny.
class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?   = false
  def show?    = false
  def create?  = false
  def new?     = create?
  def update?  = false
  def edit?    = update?
  def destroy? = false

  private

  # The matrix chokepoint every policy authorises through.
  def permit?(permission) = user&.can?(permission)

  # Legacy role shims — retained only while the 21 policies are migrated onto
  # permit?; delete once nothing references them.
  def admin?      = user&.role_admin?
  def supervisor? = user&.role_supervisor?
  def agent?      = user&.role_agent?

  # Anyone signed into the console; mutations still gated per permission.
  def staff?      = user.present?
  def can_work?   = admin? || supervisor? || agent?

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      raise NotImplementedError, "You must define #resolve in #{self.class}"
    end

    private

    def permit?(permission) = user&.can?(permission)

    def admin?      = user&.role_admin?
    def supervisor? = user&.role_supervisor?
  end
end
