class QueueMembership < ApplicationRecord
  include Audited

  belongs_to :queue, class_name: "CaseQueue"
  belongs_to :user

  validates :user_id, uniqueness: { scope: :queue_id }
end
