module Admin
  # Activity & Usage (handoff §6): the deployment owner's own
  # "who's doing what", served entirely from the local audit log and
  # sessions — never transmitted anywhere.
  class ActivityController < ApplicationController
    def index
      authorize :activity, policy_class: AdminAreaPolicy
      @from = parse_date(params[:from]) || 30.days.ago.to_date
      @to = parse_date(params[:to]) || Date.current
      range = @from.beginning_of_day..@to.end_of_day

      entries = AuditEntry.where(created_at: range)
      @actions_by_user = entries.where(actor_type: "User")
                                .group(:actor_id, :action).count
                                .each_with_object({}) do |((user_id, action), count), acc|
        (acc[user_id] ||= {})[action] = count
      end
      @users = User.with_deleted.where(id: @actions_by_user.keys).index_by(&:id)

      @logins = AuditEntry.where(action: [ "user.login", "user.login_sso" ], created_at: range)
                          .order(id: :desc).limit(50).includes(:actor)

      cases_in_range = Case.where(created_at: range)
      @volume_by_queue = cases_in_range.group(:queue_id).count
                                       .transform_keys { |id| CaseQueue.with_deleted.find_by(id: id) }
      @volume_by_staff = Case.where(created_at: range).where.not(assignee_id: nil)
                             .group(:assignee_id).count
                             .transform_keys { |id| User.with_deleted.find_by(id: id) }

      @stats = {
        cases_created: cases_in_range.count,
        cases_resolved: Case.where(resolved_at: range).count,
        sla_breaches: entries.where(action: "case.update")
                             .where("changeset LIKE ?", "%_breached%").count,
        agent_turns: Message.where(created_at: range, kind: :agent_turn).count,
        human_replies: Message.where(created_at: range, kind: :public_reply, direction: :outbound).count
      }

      respond_to do |format|
        format.html
        format.csv { send_data activity_csv, filename: "docket-activity-#{@from}-#{@to}.csv" }
      end
    end

    private

    def parse_date(value)
      Date.parse(value.to_s)
    rescue ArgumentError, TypeError
      nil
    end

    def activity_csv
      require "csv"
      CSV.generate do |csv|
        csv << %w[user email action count from to]
        @actions_by_user.each do |user_id, actions|
          user = @users[user_id]
          actions.sort.each do |action, count|
            csv << [ csv_safe(user&.name), csv_safe(user&.email_address), action, count, @from, @to ]
          end
        end
      end
    end

    # Spreadsheet formula-injection guard for text cells.
    def csv_safe(value)
      value.to_s.match?(/\A[=+\-@\t]/) ? "'#{value}" : value
    end
  end
end
