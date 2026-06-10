# Activity & Usage aggregation (handoff §6), shared by the admin view
# and GET /api/v1/reports/activity. Computed entirely from this
# deployment's own audit log and case data.
class ActivityReport
  attr_reader :from, :to

  def initialize(from:, to:)
    @from = from
    @to = to
  end

  def range
    from.beginning_of_day..to.end_of_day
  end

  # { user_id => { action => count } }
  def actions_by_user
    @actions_by_user ||= AuditEntry.where(created_at: range, actor_type: "User")
                                   .group(:actor_id, :action).count
                                   .each_with_object({}) do |((user_id, action), count), acc|
      (acc[user_id] ||= {})[action] = count
    end
  end

  def users
    @users ||= User.with_deleted.where(id: actions_by_user.keys).index_by(&:id)
  end

  def logins
    AuditEntry.where(action: [ "user.login", "user.login_sso" ], created_at: range)
              .order(id: :desc).limit(50).includes(:actor)
  end

  def volume_by_queue
    @volume_by_queue ||= Case.where(created_at: range).group(:queue_id).count
                             .transform_keys { |id| CaseQueue.with_deleted.find_by(id: id) }
  end

  def volume_by_staff
    @volume_by_staff ||= Case.where(created_at: range).where.not(assignee_id: nil)
                             .group(:assignee_id).count
                             .transform_keys { |id| User.with_deleted.find_by(id: id) }
  end

  def stats
    @stats ||= begin
      created = Case.where(created_at: range).count
      resolved_scope = Case.where(resolved_at: range)
      resolved = resolved_scope.count
      compliant = resolved_scope.where(resolution_breached: false).count
      {
        cases_created: created,
        cases_resolved: resolved,
        resolution_rate: created.zero? ? nil : (resolved * 100.0 / created).round(1),
        sla_breaches: breach_events,
        sla_compliance: resolved.zero? ? nil : (compliant * 100.0 / resolved).round(1),
        agent_turns: Message.where(created_at: range, kind: :agent_turn).count,
        human_replies: Message.where(created_at: range, kind: :public_reply, direction: :outbound).count
      }
    end
  end

  # Breach *events* in range: audited flag flips on cases.
  def breach_events
    AuditEntry.where(created_at: range, action: "case.update", auditable_type: "Case")
              .where("changeset LIKE ? OR changeset LIKE ?",
                     "%first_response_breached%", "%resolution_breached%").count
  end

  def as_json(*)
    {
      from: from,
      to: to,
      summary: stats,
      actions_by_user: actions_by_user.map do |user_id, actions|
        user = users[user_id]
        { user_id: user_id, name: user&.name, email: user&.email_address, actions: actions }
      end,
      volume_by_queue: volume_by_queue.map { |queue, count| { queue: queue&.name, queue_id: queue&.id, count: count } },
      volume_by_staff: volume_by_staff.map { |user, count| { user_id: user&.id, name: user&.name, count: count } },
      logins: logins.map do |entry|
        { actor_type: entry.actor_type, actor_id: entry.actor_id,
          name: entry.actor.respond_to?(:name) ? entry.actor.name : nil,
          method: entry.action, ip: entry.metadata&.dig("ip"), at: entry.created_at }
      end
    }
  end

  def to_csv
    require "csv"
    CSV.generate do |csv|
      csv << %w[user email action count from to]
      actions_by_user.each do |user_id, actions|
        user = users[user_id]
        actions.sort.each do |action, count|
          csv << [ csv_safe(user&.name), csv_safe(user&.email_address), action, count, from, to ]
        end
      end
    end
  end

  private

  # Spreadsheet formula-injection guard for text cells.
  def csv_safe(value)
    value.to_s.match?(/\A[=+\-@\t]/) ? "'#{value}" : value
  end
end
