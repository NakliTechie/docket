module Notifications
  class Publish
    Result = Data.define(:notification, :created, :escalated)

    def self.call(...) = new(...).call

    def initialize(recipient:, kind:, notifiable:, dedupe_key:, title:, body:,
                   severity: :info, actor: Current.effective_actor, metadata: {}, repeat: true)
      @recipient = recipient
      @kind = kind.to_s
      @notifiable = notifiable
      @dedupe_key = dedupe_key
      @title = title
      @body = body
      @severity = severity.to_s
      @actor = actor
      @metadata = metadata.stringify_keys
      @repeat = repeat
    end

    def call
      return unless deliverable_recipient?
      return if @actor.is_a?(User) && @actor.id == @recipient.id

      result = publish
      enqueue_email(result) if result.created || result.escalated
      result.notification
    rescue ActiveRecord::RecordNotUnique
      retry
    end

    private

    def publish
      Notification.transaction do
        existing = Notification.lock.find_by(user: @recipient, dedupe_key: @dedupe_key)
        existing ? update_existing(existing) : create_notification
      end
    end

    def create_notification
      notification = Notification.create!(
        user: @recipient, kind: @kind, severity: @severity, actor: @actor,
        notifiable: @notifiable, dedupe_key: @dedupe_key, title: @title, body: @body,
        metadata: @metadata, last_occurred_at: Time.current
      )
      Result.new(notification: notification, created: true, escalated: false)
    end

    def update_existing(notification)
      old_severity = Notification.severities.fetch(notification.severity)
      new_severity = Notification.severities.fetch(@severity)
      escalated = new_severity > old_severity || notification.kind != @kind
      return Result.new(notification: notification, created: false, escalated: false) if !@repeat && !escalated

      notification.update!(
        kind: @kind,
        severity: new_severity > old_severity ? @severity : notification.severity,
        actor: @actor,
        title: @title,
        body: @body,
        metadata: @metadata,
        occurrences: notification.occurrences + 1,
        last_occurred_at: Time.current,
        read_at: escalated ? nil : notification.read_at,
        email_status: :pending,
        email_claimed_at: nil,
        email_last_error: nil
      )
      Result.new(notification: notification, created: false, escalated: escalated)
    end

    def deliverable_recipient?
      @recipient.is_a?(User) && @recipient.active? && !@recipient.deleted?
    end

    def enqueue_email(result)
      return unless Setting.get("notification_email_enabled", false)

      NotificationDeliveryJob.perform_later(result.notification.id)
    end
  end
end
