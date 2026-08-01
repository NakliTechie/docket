module ApplicationHelper
  include Pagy::Frontend

  # The operator-configurable brand shown in the staff header, auth pages and
  # the customer portal. Falls back to the per-surface neutral default, then
  # the product name — so docket reads private-first out of the box and a
  # government deploy just sets its own brand.
  def brand_name(fallback = nil)
    Setting.get("brand_name").presence || fallback || t("layout.product_name")
  end

  # Format a cents amount as currency, matching the deal/lead views
  # (whole-rupee display, ₹ unit). Nil reads as zero.
  def format_cents(cents)
    number_to_currency((cents || 0) / 100.0, unit: "₹", precision: 0)
  end

  def format_money(cents, currency)
    code = currency.to_s.upcase.presence || "INR"
    number_to_currency((cents || 0) / 100.0, unit: "#{code} ", precision: 2)
  end

  def format_money_totals(totals)
    return format_money(0, "INR") if totals.blank?

    safe_join(totals.sort.map { |currency, cents| tag.span(format_money(cents, currency)) }, tag.br)
  end

  # Inline SVG sprite reference (vendored icons, no icon font, no CDN).
  def icon(name, size: 16, **options)
    options[:class] = [ "icon", options[:class] ].compact.join(" ")
    tag.svg(width: size, height: size, aria: { hidden: true }, **options) do
      tag.use(href: "#{image_path("icons.svg")}#icon-#{name}")
    end
  end

  def status_badge(kase)
    tag.span(kase.human_status, class: "badge badge-status status-#{kase.status.dasherize}")
  end

  def priority_badge(kase)
    tag.span(kase.human_priority, class: "badge badge-priority priority-#{kase.priority}")
  end

  def role_badge(user)
    tag.span(user.human_role, class: "badge badge-role role-#{user.role}")
  end

  def sla_chip(kase)
    if kase.first_response_breached || kase.resolution_breached
      tag.span(t("cases.sla.breached"), class: "badge badge-sla sla-breached")
    elsif kase.resolution_due_at && kase.open?
      tag.span(t("cases.sla.due", time: time_ago_label(kase.resolution_due_at)),
               class: "badge badge-sla #{kase.resolution_due_at.past? ? "sla-overdue" : "sla-ok"}")
    end
  end

  def time_ago_label(time)
    return "" if time.blank?
    time.past? ? t("time.ago", time: time_ago_in_words(time)) : t("time.in", time: time_ago_in_words(time))
  end

  # Link one Customer360::Event to the record it happened on. The event kind
  # decides the target; the module that produced the event is already known to
  # be entitled (its scope wasn't Model.none), so no re-gating is needed here.
  def customer_360_event_link(event)
    record = event.record
    case event.kind
    when :message
      # String#truncate (plain String), not the truncate() view helper — the
      # helper HTML-escapes and returns html_safe, which then gets escaped a
      # second time by link_to, rendering "can&#39;t" instead of "can't".
      link_to "#{record.case.tracking_id} · #{record.body.to_s.truncate(80)}", case_path(record.case)
    when :deal_opened, :deal_won, :deal_lost
      link_to record.name, deal_path(record)
    when :work_opened, :work_closed
      link_to "#{record.reference} · #{record.title}", work_item_path(record)
    else # case_opened / case_resolved / case_closed
      link_to "#{record.tracking_id} · #{record.subject}", case_path(record)
    end
  end

  def page_title(title = nil)
    content_for(:title) { title } if title
    [ content_for(:title), t("layout.product_name") ].compact_blank.join(" · ")
  end

  def page_description(description = nil)
    content_for(:description) { description } if description
    content_for(:description)
  end

  def nav_link(label, path, active: false)
    link_to label, path, class: class_names("nav-link", active: active),
            aria: { current: active ? "page" : nil }
  end

  # A collapsible nav dropdown (CSS-only <details>), keeping the top bar short.
  # `active` highlights the group when one of its pages is current.
  def nav_group(label, active: false)
    content = capture { yield }
    tag.details(class: class_names("nav-group", active: active),
                data: { action: "toggle->navigation#groupToggled" }) do
      tag.summary(label, class: class_names("nav-link", "nav-group-toggle", active: active)) +
        tag.div(content, class: "nav-menu")
    end
  end

  def nav_section(label)
    tag.span(label, class: "nav-menu-section")
  end

  def first_run_setup?
    return false unless authenticated? && Current.user
    return false unless PlatformAreaPolicy.new(Current.user, :settings).show?

    @first_run_setup ||= SetupProgress.new(actor: Current.user, base_url: request.base_url)
                                      .needs_attention?
  end

  # Single-key status shortcuts on the case view; documented in the
  # in-app help modal.
  TRANSITION_SHORTCUTS = {
    "triaged" => "t", "in_progress" => "s", "waiting_on_customer" => "w",
    "resolved" => "r", "closed" => "c", "reopened" => "o"
  }.freeze

  def transition_shortcut(status)
    TRANSITION_SHORTCUTS[status.to_s]
  end
end
