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
    @logins ||= AuditEntry.where(action: [ "user.login", "user.login_sso" ], created_at: range)
                          .order(id: :desc).limit(50).includes(:actor)
  end

  # Reports measure what happened in the window, so a case/message later
  # soft-deleted still counts — otherwise deleting a record silently
  # rewrites past usage figures. (with_deleted throughout.)
  def volume_by_queue
    @volume_by_queue ||= Case.with_deleted.where(created_at: range).group(:queue_id).count
                             .transform_keys { |id| CaseQueue.with_deleted.find_by(id: id) }
  end

  def volume_by_staff
    @volume_by_staff ||= Case.with_deleted.where(created_at: range).where.not(assignee_id: nil)
                             .group(:assignee_id).count
                             .transform_keys { |id| User.with_deleted.find_by(id: id) }
  end

  def stats
    @stats ||= begin
      created = Case.with_deleted.where(created_at: range).count
      resolved_scope = Case.with_deleted.where(resolved_at: range)
      resolved = resolved_scope.count
      compliant = resolved_scope.where(resolution_breached: false).count
      {
        cases_created: created,
        cases_resolved: resolved,
        resolution_rate: created.zero? ? nil : (resolved * 100.0 / created).round(1),
        sla_breaches: breach_events,
        sla_compliance: resolved.zero? ? nil : (compliant * 100.0 / resolved).round(1),
        agent_turns: Message.with_deleted.where(created_at: range, kind: :agent_turn).count,
        human_replies: Message.with_deleted.where(created_at: range, kind: :public_reply, direction: :outbound).count
      }
    end
  end

  # Breach *events* in range: count audited flips of a breach flag TO true.
  # The old `changeset LIKE '%..breached%'` row-count also caught flags
  # cleared back to false (a correction) and any incidental substring
  # match — both inflated the figure. Parse the json changeset and count
  # only `[_, true]` transitions (a single update flipping both flags = 2).
  def breach_events
    AuditEntry.where(created_at: range, action: "case.update", auditable_type: "Case")
              .where("changeset LIKE ? OR changeset LIKE ?",
                     "%first_response_breached%", "%resolution_breached%")
              .sum { |entry| breach_flips(entry.changeset) }
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

  # How many breach flags this audited changeset flipped TO true.
  def breach_flips(changeset)
    return 0 unless changeset.is_a?(Hash)
    %w[first_response_breached resolution_breached].count do |flag|
      change = changeset[flag]
      change.is_a?(Array) && change.last == true
    end
  end

  # Spreadsheet formula-injection guard for text cells.
  def csv_safe(value)
    value.to_s.match?(/\A[=+\-@\t]/) ? "'#{value}" : value
  end
end
