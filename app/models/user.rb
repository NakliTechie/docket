class User < ApplicationRecord
  include SoftDeletable
  include Audited
  include HumanEnums

  humanizes_enums :role

  has_secure_password

  # Method names prefixed (user.role_admin?) because a bare `readonly?`
  # would collide with ActiveRecord; stored values stay admin/supervisor/
  # agent/readonly for UI and API.
  enum :role, { admin: 0, supervisor: 1, agent: 2, readonly: 3 }, default: :agent, prefix: true

  has_many :sessions, dependent: :destroy
  has_many :queue_memberships, dependent: :destroy
  has_many :queues, through: :queue_memberships, source: :queue
  has_many :assigned_cases, class_name: "Case", foreign_key: :assignee_id, dependent: nil, inverse_of: :assignee

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true,
            format: { with: URI::MailTo::EMAIL_REGEXP }

  scope :active, -> { where(active: true) }
  scope :staff, -> { where(role: [ :admin, :supervisor, :agent ]) }

  def deactivate!
    transaction do
      update!(active: false)
      sessions.delete_all
    end
  end

  def display_label
    "#{name} (#{email_address})"
  end
end
