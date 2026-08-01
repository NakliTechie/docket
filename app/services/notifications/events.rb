module Notifications
  module Events
    module_function

    def case_assigned(kase)
      return if suppressed? || kase.assignee.nil?

      publish(
        recipient: kase.assignee, kind: :assignment, notifiable: kase,
        dedupe_key: "case:#{kase.id}:assignment:#{kase.assignee_id}:#{kase.updated_at.to_f}",
        title: "Case assigned to you", body: "#{kase.tracking_id}: #{kase.subject}",
        metadata: { reference: kase.tracking_id, subject: kase.subject }
      )
    end

    def work_assigned(item)
      return if suppressed? || item.assignee.nil?

      publish(
        recipient: item.assignee, kind: :assignment, notifiable: item,
        dedupe_key: "work:#{item.id}:assignment:#{item.assignee_id}:#{item.updated_at.to_f}",
        title: "Work assigned to you", body: "#{item.reference}: #{item.title}",
        metadata: { reference: item.reference, subject: item.title }
      )
    end

    def mentions(source)
      return if suppressed? || !source.author.is_a?(User)

      notifiable = source.is_a?(Message) ? source.case : source.work_item
      Mentions.users_in(source.body).find_each do |recipient|
        publish(
          recipient: recipient, kind: :mention, notifiable: notifiable, actor: source.author,
          dedupe_key: "#{source.model_name.param_key}:#{source.id}:mention:#{recipient.id}",
          title: "You were mentioned",
          body: "#{source.author.name} mentioned you on #{reference(notifiable)}",
          metadata: { actor: source.author.name, reference: reference(notifiable) }
        )
      end
    end

    def watched_work(item, event:, source: nil)
      return if suppressed?

      actor = source&.respond_to?(:author) ? source.author : Current.effective_actor
      item.watchers.active.find_each do |recipient|
        publish(
          recipient: recipient, kind: :watched_work, notifiable: item, actor: actor,
          dedupe_key: watched_work_key(item, event, source, recipient),
          title: "Watched work changed", body: watched_work_body(item, event),
          metadata: { reference: item.reference, subject: item.title, event: event.to_s }
        )
      end
    end

    # PG3: alert a notify-user that a case reached an escalation level. (The new
    # assignee, if any, is separately notified by the case_assigned hook.)
    def case_escalated(kase, recipient, level:)
      return if suppressed? || recipient.nil?

      publish(
        recipient: recipient, kind: :escalation, severity: :critical, notifiable: kase,
        dedupe_key: "case:#{kase.id}:escalation:level:#{level.id}",
        title: "Case escalated",
        body: "#{kase.tracking_id}: #{kase.subject} escalated (tier at +#{level.after_minutes} min)",
        metadata: { reference: kase.tracking_id, subject: kase.subject, after_minutes: level.after_minutes }
      )
    end

    def sla_risk(kase, clock)
      publish_sla(kase, clock, kind: :sla_risk, severity: :warning, repeat: false)
    end

    def sla_breach(kase, clock)
      publish_sla(kase, clock, kind: :sla_breach, severity: :critical, repeat: false)
    end

    def recipients_for_case(kase)
      recipients = [ kase.assignee ].compact.select(&:active?)
      recipients = kase.queue.members.active.to_a if recipients.empty? && kase.queue
      if recipients.empty?
        recipients = User.active.where(role: %i[client_admin super_admin]).to_a
      end
      recipients.uniq(&:id)
    end

    def publish_sla(kase, clock, kind:, severity:, repeat:)
      return if suppressed?

      label = clock.to_s.tr("_", " ")
      recipients_for_case(kase).each do |recipient|
        publish(
          recipient: recipient, kind: kind, severity: severity, notifiable: kase,
          dedupe_key: "case:#{kase.id}:sla:#{clock}", repeat: repeat,
          title: kind == :sla_breach ? "SLA breached" : "SLA at risk",
          body: "#{kase.tracking_id} #{label} SLA #{kind == :sla_breach ? "breached" : "is at risk"}",
          metadata: { reference: kase.tracking_id, clock: label }
        )
      end
    end
    private_class_method :publish_sla

    def publish(**attributes)
      Publish.call(**attributes)
    end
    private_class_method :publish

    def suppressed? = Imports::Mode.running?
    private_class_method :suppressed?

    def reference(record)
      record.is_a?(Case) ? record.tracking_id : record.reference
    end
    private_class_method :reference

    def watched_work_key(item, event, source, recipient)
      source_key = source ? "#{source.model_name.param_key}:#{source.id}" : item.updated_at.to_f
      "work:#{item.id}:watch:#{event}:#{source_key}:#{recipient.id}"
    end
    private_class_method :watched_work_key

    def watched_work_body(item, event)
      action = event.to_sym == :commented ? "received a comment" : "moved to #{item.workflow_state.name}"
      "#{item.reference}: #{item.title} #{action}"
    end
    private_class_method :watched_work_body
  end
end
