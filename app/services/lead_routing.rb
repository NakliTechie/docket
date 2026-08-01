# Applies the declarative lead-routing rules on lead creation — the lead-side
# complement to CaseRouting. The first matching active rule (in position order)
# wins and assigns an owner by strategy. A no-op when no rule matches or the
# matched rule yields no eligible owner (so the lead simply stays unowned).
#
# Called from Lead's after_create hook, so console, API, and connector-created
# leads all route through one seam. Skipped for import-sourced or already-owned
# leads (see Lead#skip_auto_routing?).
module LeadRouting
  module_function

  # → the matching LeadRoutingRule (truthy) or false.
  def apply(lead)
    rule = LeadRoutingRule.active.ordered.detect { |candidate| candidate.matches?(lead) }
    return false unless rule

    owner = Assignment.for(rule)
    lead.update!(owner: owner) if owner
    rule
  end

  # Picks an owner per the rule's strategy from the lead-owner pool. Returns nil
  # to leave the lead unowned (empty pool / ineligible specific user).
  module Assignment
    module_function

    def for(rule)
      case rule.then_assignment
      when "specific_user" then (rule.then_owner if eligible?(rule.then_owner))
      when "round_robin"   then round_robin
      when "least_loaded"  then least_loaded
      end
    end

    # Active users who may own a lead. Small user counts → an in-memory filter
    # over the permission matrix rather than a bespoke column.
    def pool
      User.where(active: true).order(:id).select { |user| user.can?("lead:write") }
    end

    def eligible?(user)
      user.present? && user.active? && user.can?("lead:write")
    end

    # Stateless rotation: distribute by the tenant's canonical lead count.
    def round_robin
      candidates = pool
      return nil if candidates.empty?
      candidates[Lead.canonical.count % candidates.size]
    end

    # The eligible owner with the fewest open leads.
    def least_loaded
      candidates = pool
      return nil if candidates.empty?
      candidates.min_by { |user| Lead.open_leads.where(owner_id: user.id).count }
    end
  end
end
