# Admin-managed canned responses with variable interpolation
# (handoff §7). Inserted into the composer client-side; the message
# saved is a plain Message — no special casing downstream.
class Macro < ApplicationRecord
  include SoftDeletable
  include Audited

  VARIABLES = %w[contact_name tracking_id agent_name queue_name].freeze

  validates :name, presence: true, uniqueness: { conditions: -> { where(deleted_at: nil) } }
  validates :body, presence: true

  def render_for(kase, agent: nil)
    body.gsub(/\{\{\s*(\w+)\s*\}\}/) do
      case Regexp.last_match(1)
      when "contact_name" then kase.contact&.name
      when "tracking_id"  then kase.tracking_id
      when "agent_name"   then agent&.name
      when "queue_name"   then kase.queue&.name
      else Regexp.last_match(0)
      end.to_s
    end
  end
end
