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

  def page_title(title = nil)
    content_for(:title) { title } if title
    [ content_for(:title), t("layout.product_name") ].compact_blank.join(" · ")
  end

  def nav_link(label, path, active: false)
    link_to label, path, class: class_names("nav-link", active: active),
            aria: { current: active ? "page" : nil }
  end

  # A collapsible nav dropdown (CSS-only <details>), keeping the top bar short.
  # `active` highlights the group when one of its pages is current.
  def nav_group(label, active: false)
    content = capture { yield }
    tag.details(class: class_names("nav-group", active: active)) do
      tag.summary(label, class: class_names("nav-link", "nav-group-toggle", active: active)) +
        tag.div(content, class: "nav-menu")
    end
  end

  # Single-key status shortcuts on the case view; documented in the
  # in-app help modal.
  TRANSITION_SHORTCUTS = {
    "triaged" => "t", "in_progress" => "s", "waiting_on_citizen" => "w",
    "resolved" => "r", "closed" => "c", "reopened" => "o"
  }.freeze

  def transition_shortcut(status)
    TRANSITION_SHORTCUTS[status.to_s]
  end
end
