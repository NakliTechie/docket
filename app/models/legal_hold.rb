class LegalHold < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :subject, polymorphic: true
  belongs_to :placed_by, -> { with_deleted }, class_name: "User", optional: true
  belongs_to :released_by, -> { with_deleted }, class_name: "User", optional: true

  validates :reason, presence: true

  scope :active, -> {
    where(released_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  def release!(actor: Current.user)
    update!(released_at: Time.current, released_by: actor)
  end
end
