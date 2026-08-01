class SlaRiskSweepJob < ApplicationJob
  queue_as :default

  def perform
    Current.set(actor: nil) do
      each_tenant_with_feature("service_desk") do
        Case.open_cases.find_each { |kase| notify_risk(kase) }
      end
    end
    record_sweep_success!
  end

  private

  def notify_risk(kase)
    threshold = Setting.get("sla_risk_minutes", 60).to_i
    notify_clock(kase, :first_response, kase.first_response_due_at, threshold) unless kase.first_responded_at
    notify_clock(kase, :resolution, kase.resolution_due_at, threshold)
  end

  def notify_clock(kase, clock, due_at, threshold)
    return if due_at.nil? || due_at <= Time.current
    return if clock == :first_response && kase.first_response_breached?
    return if clock == :resolution && kase.resolution_breached?
    return if business_minutes_remaining(kase, due_at) > threshold

    Notifications::Events.sla_risk(kase, clock)
  end

  def business_minutes_remaining(kase, due_at)
    calendar = SlaClock.calendar_for(kase)
    return ((due_at - Time.current) / 60).ceil unless calendar

    BusinessTime.minutes_between(calendar: calendar, from: Time.current, to: due_at)
  end
end
