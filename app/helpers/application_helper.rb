module ApplicationHelper
  include Pagy::Frontend

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
end
