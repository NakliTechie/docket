class User < ApplicationRecord
  acts_as_tenant(:tenant)
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :role

  has_secure_password

  # Method names prefixed (user.role_super_admin?) because a bare `readonly?`
  # would collide with ActiveRecord. Authority for every role comes from
  # Authz::ROLE_PERMISSIONS via #can?, never from a bare role name. (The legacy
  # admin/supervisor/agent values were retired by the MigrateLegacyRoles
  # cutover.) See plan/rbac-research-2026-06-13.md.
  enum :role, {
    super_admin: 4, client_admin: 5, finance: 6, sales: 7,
    customer_service: 8, technical: 9, readonly: 3
  }, default: :customer_service, prefix: true

  # Authority ordering for "who may grant which role" (C2) — NOT the enum's
  # storage integers. super_admin is the cross-tenant platform tier; a role can
  # only be granted by an actor of equal-or-higher rank. Also the SSO claim→role
  # precedence (highest wins).
  ROLE_RANK = {
    "super_admin" => 6, "client_admin" => 5, "finance" => 4, "technical" => 3,
    "sales" => 2, "customer_service" => 1, "readonly" => 0
  }.freeze

  def self.role_rank(role) = ROLE_RANK.fetch(role.to_s, -1)

  has_many :sessions, dependent: :destroy
  has_many :queue_memberships, dependent: :destroy
  has_many :queues, through: :queue_memberships, source: :queue
  has_many :assigned_cases, class_name: "Case", foreign_key: :assignee_id, dependent: nil, inverse_of: :assignee

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  # Scope uniqueness to live rows so a soft-deleted user's email can be
  # re-provisioned (e.g. an offboarded staffer returning via SSO). Matches
  # every other SoftDeletable model; the DB index is partial to match.
  validates :email_address, presence: true,
            uniqueness: { scope: :tenant_id, conditions: -> { where(deleted_at: nil) } },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  # A user can only be granted a role at or below the acting user's own rank, so
  # a per-tenant client_admin can't mint a cross-tenant super_admin (C2).
  # Enforced at the model so every path (admin UI, API, future) is covered;
  # bootstrap/seed/migration context (no acting user) is unconstrained.
  validate :role_within_assigner_authority, if: -> { new_record? || will_save_change_to_role? }

  scope :active, -> { where(active: true) }
  # Operational staff who can own records / staff queues — everyone except
  # readonly. (Was [admin, supervisor, agent]; equivalent now that the legacy
  # roles are the only other non-readonly roles, and it extends to the new
  # functional roles for free.)
  scope :staff, -> { where.not(role: :readonly) }

  # The single authority chokepoint. Policies and the effector gate ask this,
  # never a bare role name. When tenancy lands, a `tenant:` keyword is added
  # here (super_admin is cross-tenant, client_admin per-tenant) — call sites
  # pass no tenant today, so none of them change. See plan/rbac-research.
  def can?(permission)
    Authz.permissions_for(role).include?(permission.to_s)
  end

  def deactivate!
    transaction do
      update!(active: false)
      sessions.delete_all
    end
  end

  def display_label
    "#{name} (#{email_address})"
  end

  private

  def role_within_assigner_authority
    assigner = Current.effective_actor
    return unless assigner.is_a?(User) # system / seed / migration → unconstrained
    return if self.class.role_rank(role) <= self.class.role_rank(assigner.role)
    errors.add(:role, :exceeds_assigner)
  end
end
