# Case classification vocabulary. +ai_auto_resolve+ is the per-category
# gate an admin flips to let the AI resolve autonomously (handoff §4) —
# OFF by default, always.
class Category < ApplicationRecord
  include SoftDeletable
  include Audited

  has_many :cases, dependent: nil

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
end
