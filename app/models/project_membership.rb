# Membership of a project — the pool round-robin assignment draws from, and the
# default audience for project-scoped views.
class ProjectMembership < ApplicationRecord
  acts_as_tenant(:tenant)
  include Audited

  belongs_to :project
  belongs_to :user, -> { with_deleted }

  validates :user_id, uniqueness: { scope: :project_id }

  def display_label = "#{user&.name} on #{project&.key}"
end
