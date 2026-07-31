class PrivacyErasureRequest < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  enum :status, { pending: 0, completed: 1, failed: 2 }, prefix: true

  belongs_to :subject, polymorphic: true
  belongs_to :requested_by, -> { with_deleted }, class_name: "User", optional: true

  validates :erasure_token, presence: true, uniqueness: true
end
