module ApplicationHelper
  # Dark text on light colors, white text on dark ones.
  def readable_text_color(hex)
    r, g, b = hex.delete("#").scan(/../).map { |c| c.to_i(16) }
    ((r * 299) + (g * 587) + (b * 114)) / 1000 >= 150 ? "#212529" : "#ffffff"
  end

  # A colored pill for a status (used on the admin screens now, and the board later).
  def status_pill(status, label = nil)
    tag.span(label || status.name, class: "badge rounded-pill",
             style: "background-color: #{status.color}; color: #{readable_text_color(status.color)}")
  end

  def nav_link(label, path, active: current_page?(path))
    link_to label, path, class: "nav-link #{'active' if active}"
  end

  # 754 seconds -> "12:34"; 4_000 -> "1:06:40". Matches what the page's live timers show.
  def format_elapsed(seconds)
    total = [ seconds.to_i, 0 ].max
    h, rest = total.divmod(3600)
    m, s = rest.divmod(60)
    h.positive? ? format("%d:%02d:%02d", h, m, s) : format("%d:%02d", m, s)
  end

  # Clock time for today, with the date added for anything earlier so a long-running status isn't misread.
  def event_time(time)
    local = time.in_time_zone
    local.to_date == Time.current.to_date ? local.strftime("%-I:%M:%S %p") : local.strftime("%b %-d, %-I:%M:%S %p")
  end
end
