module DashboardsHelper
  # A tiny inline-SVG line chart for a daily series — zero JS, zero dependency,
  # themeable via `currentColor`. `series` is an array of { date:, count: }
  # (OperationalReport#cases_created_trend). Scales to fill its container.
  def sparkline(series, width: 320, height: 48)
    counts = Array(series).map { |point| point[:count].to_i }
    return content_tag(:p, t("dashboards.index.no_trend"), class: "muted") if counts.empty?

    max = [ counts.max, 1 ].max
    pad = 4
    step = counts.length > 1 ? width.to_f / (counts.length - 1) : 0.0
    points = counts.each_with_index.map do |count, i|
      x = (i * step).round(1)
      y = (height - pad - (count.to_f / max) * (height - 2 * pad)).round(1)
      "#{x},#{y}"
    end.join(" ")

    content_tag(:svg, class: "sparkline", width: width, height: height,
                viewBox: "0 0 #{width} #{height}", preserveAspectRatio: "none",
                role: "img", "aria-label": t("dashboards.index.trend_aria", count: counts.sum)) do
      tag.polyline(points: points, fill: "none", stroke: "currentColor", "stroke-width": 2,
                   "stroke-linejoin": "round", "stroke-linecap": "round")
    end
  end
end
