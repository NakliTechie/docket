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

  # The matrix chokepoint every policy authorises through. (The legacy
  # admin?/supervisor?/agent?/can_work?/staff? shims were removed once the
  # cutover left them unreferenced — S1; they also referenced retired enum
  # predicates and would have raised if called.)
  def permit?(permission) = user&.can?(permission)

  def record_in_scope?(access)
    RecordVisibility.allowed?(user, record, access: access)
  end

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

    def record_scope(access: :read)
      RecordVisibility.resolve(user, scope, access: access)
    end
  end
end
