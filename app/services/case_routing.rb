# Applies the declarative routing rules to a case on intake — the deterministic
# complement to the AI triage agent. The first matching active rule (in position
# order) wins: it sets queue/category/priority, picks an assignee by strategy,
# and stamps `routed_by_rule_id` (which makes the AI agent skip re-classification
# but still draft/resolve). If no AI loop will run for this case, the rule also
# completes triage (→ :triaged) itself. A no-op when no rule matches.
module CaseRouting
  module_function

  # → the matching RoutingRule (truthy) or false.
  def apply(kase)
    rule = RoutingRule.active.ordered.detect { |r| r.matches?(kase) }
    return false unless rule

    attrs = { routed_by_rule_id: rule.id }
    attrs[:queue] = rule.then_queue if rule.then_queue_id
    attrs[:category] = rule.then_category if rule.then_category_id
    attrs[:priority] = rule.then_priority if rule.then_priority.present?
    assignee = Assignment.for(rule, kase)
    attrs[:assignee] = assignee if assignee
    kase.update!(attrs)

    # No AI loop will triage this case → the rule's routing is its triage.
    kase.transition_to!(:triaged) if kase.status_new? && !kase.ai_triage_eligible?
    rule
  end

  # Picks an assignee from the target queue's active members per the rule's
  # strategy. Returns nil to leave the case unassigned (keep / no members).
  module Assignment
    module_function

    def for(rule, kase)
      queue = rule.then_queue || kase.queue
      return nil unless queue

      case rule.then_assignment
      when "specific_user" then (rule.then_assignee if rule.then_assignee&.active?)
      when "round_robin"   then round_robin(queue)
      when "least_loaded"  then least_loaded(queue)
      end
    end

    def members(queue)
      queue.members.where(active: true).order(:id).to_a
    end

    # Stateless rotation: distribute by the queue's case count.
    def round_robin(queue)
      pool = members(queue)
      return nil if pool.empty?
      pool[Case.where(queue_id: queue.id).count % pool.size]
    end

    # The active member with the fewest open assigned cases.
    def least_loaded(queue)
      pool = members(queue)
      return nil if pool.empty?
      pool.min_by { |u| Case.open_cases.where(assignee_id: u.id).count }
    end
  end
end
