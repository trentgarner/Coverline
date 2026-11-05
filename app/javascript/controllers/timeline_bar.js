// Drawing helpers for the horizontal "today" bar, shared by the board and the agent page.
// An event is [startMs, endMs | null (still going), statusId].

export function escapeHtml(text) {
  return String(text).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c])
}

export function textColor(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
  return (r * 299 + g * 587 + b * 114) / 1000 >= 150 ? "#212529" : "#ffffff"
}

// Whole-hour boundaries in the organization's time zone (works for zones on a half hour too).
export function floorToHour(ms, timeZone) {
  const parts = new Intl.DateTimeFormat("en-US", { timeZone, minute: "numeric", second: "numeric", hourCycle: "h23" }).formatToParts(ms)
  const get = (type) => Number(parts.find((p) => p.type === type)?.value || 0)
  return ms - get("minute") * 60000 - get("second") * 1000 - (ms % 1000)
}

// The time span all bars share: from the first status change today (on the hour) to a little past now,
// and never narrower than 8 hours.
export function computeAxis(eventLists, dayStart, now, timeZone) {
  const starts = eventLists.flatMap((events) => events.map((e) => Math.max(e[0], dayStart)))
  const earliest = starts.length ? Math.min(...starts) : now - 4 * 3600000
  const start = floorToHour(earliest, timeZone)
  const end = Math.max(floorToHour(now, timeZone) + 2 * 3600000, start + 8 * 3600000)
  return { start, end, span: end - start }
}

export function drawAxis(element, axis, timeZone) {
  const signature = `${axis.start}|${axis.end}`
  if (element.dataset.signature === signature) return
  element.dataset.signature = signature
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric" })
  let html = ""
  for (let t = axis.start; t < axis.end; t += 3600000) {
    html += `<span class="board-tick" style="left:${((t - axis.start) / axis.span) * 100}%">${fmt.format(t).replace(" ", "").toLowerCase()}</span>`
  }
  element.innerHTML = html
}

export function segmentsHtml(events, axis, now, statuses, timeZone) {
  const fmt = new Intl.DateTimeFormat("en-US", { timeZone, hour: "numeric", minute: "2-digit" })
  const pct = (ms) => ((Math.min(Math.max(ms, axis.start), axis.end) - axis.start) / axis.span) * 100
  const html = events.map(([from, to, statusId]) => {
    const left = pct(from)
    const width = pct(to ?? now) - left
    if (width <= 0) return ""
    const status = statuses[statusId] || { name: "Status", color: "#adb5bd" }
    const title = `${status.name} ${fmt.format(from)}–${to ? fmt.format(to) : "now"}`
    return `<span class="board-seg" style="left:${left}%;width:${width}%;background-color:${status.color}" title="${escapeHtml(title)}"></span>`
  }).join("")
  return `${html}<span class="board-now" style="left:${pct(now)}%"></span>`
}
