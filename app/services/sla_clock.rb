module SlaClock
  module_function

  def deadline(calendar:, from:, minutes:)
    return from + minutes.minutes unless calendar

    BusinessTime.add_minutes(calendar: calendar, from: from, minutes: minutes)
  end

  def start!(kase, reason: "case_created", at: kase.created_at || Time.current)
    append(kase, :first_response, :started, at: at, reason: reason,
           remaining: target_for(kase)&.first_response_minutes) if kase.first_response_due_at
    append(kase, :resolution, :started, at: at, reason: reason,
           remaining: target_for(kase)&.resolution_minutes) if kase.resolution_due_at
  end

  def transition!(kase, from:, to:, at: Time.current)
    if to == "waiting_on_customer" && from != "waiting_on_customer"
      pause_resolution!(kase, at: at)
    elsif from == "waiting_on_customer" && %w[resolved closed].include?(to)
      stop_resolution!(kase, at: at, reason: to)
    elsif from == "waiting_on_customer"
      resume_resolution!(kase, at: at)
    elsif to == "reopened"
      restart_resolution!(kase, at: at)
    elsif %w[resolved closed].include?(to)
      stop_resolution!(kase, at: at, reason: to)
    end
  end

  def stop_first_response!(kase, at: Time.current)
    append(kase, :first_response, :stopped, at: at, reason: "first_response")
  end

  def breach!(kase, clock, at: Time.current)
    append(kase, clock, :breached, at: at, reason: "deadline_elapsed")
  end

  def recalculate!(kase, clock, at: Time.current)
    due = clock.to_sym == :first_response ? kase.first_response_due_at : kase.resolution_due_at
    append(kase, clock, :recalculated, at: at, reason: "sla_inputs_changed",
           metadata: { "due_at" => due&.iso8601 })
  end

  def pause_resolution!(kase, at: Time.current)
    return if kase.resolution_due_at.nil? || kase.resolution_paused_at.present?

    remaining = remaining_minutes(kase, at)
    kase.update_columns(resolution_due_at: nil, resolution_paused_at: at,
                        resolution_remaining_minutes: remaining)
    append(kase, :resolution, :paused, at: at, reason: "waiting_on_customer",
           remaining: remaining)
  end

  def resume_resolution!(kase, at: Time.current)
    remaining = kase.resolution_remaining_minutes
    return if remaining.nil?

    due = deadline(calendar: calendar_for(kase), from: at, minutes: remaining)
    kase.update_columns(resolution_due_at: due, resolution_paused_at: nil,
                        resolution_remaining_minutes: nil)
    append(kase, :resolution, :resumed, at: at, reason: "customer_wait_ended",
           remaining: remaining, metadata: { "due_at" => due.iso8601 })
  end

  def stop_resolution!(kase, at:, reason:)
    if kase.resolution_paused_at
      remaining = kase.resolution_remaining_minutes.to_i
      due = deadline(calendar: calendar_for(kase), from: at, minutes: remaining)
      kase.update_columns(resolution_due_at: due, resolution_paused_at: nil,
                          resolution_remaining_minutes: nil)
    end
    append(kase, :resolution, :stopped, at: at, reason: reason)
  end

  def restart_resolution!(kase, at: Time.current)
    minutes = target_for(kase)&.resolution_minutes
    return unless minutes

    due = deadline(calendar: calendar_for(kase), from: at, minutes: minutes)
    kase.update_columns(resolution_due_at: due, resolution_paused_at: nil,
                        resolution_remaining_minutes: nil)
    append(kase, :resolution, :started, at: at, reason: "reopened",
           remaining: minutes, metadata: { "due_at" => due.iso8601 })
  end

  def remaining_minutes(kase, at)
    calendar = calendar_for(kase)
    if calendar
      BusinessTime.minutes_between(calendar: calendar, from: at, to: kase.resolution_due_at)
    else
      [ ((kase.resolution_due_at - at) / 60).ceil, 0 ].max
    end
  end

  def calendar_for(kase)
    kase.sla_policy&.business_calendar || BusinessCalendar.default
  end

  def target_for(kase)
    kase.sla_policy&.target_for(kase.priority)
  end

  def append(kase, clock, event, at:, reason:, remaining: nil, metadata: nil)
    kase.sla_clock_events.create!(clock_kind: clock, event_kind: event,
                                  occurred_at: at, reason: reason,
                                  remaining_minutes: remaining, metadata: metadata)
  end
end
