import { Controller } from "@hotwired/stimulus"
import { computeAxis, drawAxis, segmentsHtml, escapeHtml, textColor } from "controllers/timeline_bar"

// The live board. The server renders every agent once; after that, Turbo Streams swap single rows
// as statuses change. This controller keeps the page right as that happens: filters, sorting,
// the footer counts, the flash on a changed row, the horizontal status bars, and the Live badge.
// (Time-in-status timers are the separate "elapsed" controller.)
export default class extends Controller {
  static targets = ["search", "team", "statusFilter", "sort", "totals", "count", "empty", "axis", "live", "bar"]
  static values = { statuses: Object, timeZone: String, dayStart: Number }

  connect() {
    this.loadedAt = Date.now()
    this.serverOffset = Number(this.element.dataset.elapsedServerNowValue || 0) - this.loadedAt
    this.lastStatus = new Map()
    this.firstPass = true
    this.restoreFromUrl()
    this.observer = new MutationObserver((mutations) => {
      const rowsChanged = mutations.some((m) => [...m.addedNodes].some((n) => n.nodeType === 1 && n.matches?.("tr.board-row")))
      if (rowsChanged) this.apply()
    })
    this.watch()
    this.apply()
    this.refreshTimer = setInterval(() => this.apply(), 30000) // moves the "now" line
    this.liveTimer = setInterval(() => this.updateLive(), 1000)
    this.onMorph = () => { this.restoreFromUrl(); this.watch(); this.apply() }
    document.addEventListener("turbo:morph", this.onMorph)
    this.updateLive()
  }

  disconnect() {
    this.observer?.disconnect()
    clearInterval(this.refreshTimer)
    clearInterval(this.liveTimer)
    document.removeEventListener("turbo:morph", this.onMorph)
  }

  watch() {
    this.observer.disconnect()
    this.observer.observe(this.element.querySelector("table"), { childList: true, subtree: true })
  }

  // --- controls -------------------------------------------------------------------------------

  changed() { this.saveToUrl(); this.apply() }

  reset() {
    this.searchTarget.value = ""
    this.teamTarget.value = ""
    this.statusFilterTarget.value = ""
    this.sortTarget.value = "name"
    this.changed()
  }

  saveToUrl() {
    const params = new URLSearchParams()
    const set = (key, value, fallback = "") => { if (value && value !== fallback) params.set(key, value) }
    set("q", this.searchTarget.value.trim())
    set("team", this.teamTarget.value)
    set("status", this.statusFilterTarget.value)
    set("sort", this.sortTarget.value, "name")
    const query = params.toString()
    history.replaceState(history.state, "", query ? `${location.pathname}?${query}` : location.pathname)
  }

  restoreFromUrl() {
    const params = new URLSearchParams(location.search)
    this.searchTarget.value = params.get("q") || ""
    this.teamTarget.value = params.get("team") || ""
    this.statusFilterTarget.value = params.get("status") || ""
    this.sortTarget.value = params.get("sort") || "name"
  }

  // --- the main pass: flash, filter, sort, count, draw ----------------------------------------

  apply() {
    this.observer.disconnect() // our own changes must not trigger another pass
    const rows = [...this.element.querySelectorAll("tr.board-row")]
    this.flashChanged(rows)
    this.filter(rows)
    this.sortGroups()
    this.updateTotals(rows)
    this.drawBars(rows)
    this.watch()
  }

  flashChanged(rows) {
    rows.forEach((row) => {
      const id = row.dataset.userId
      const status = row.dataset.statusId
      if (!this.firstPass && this.lastStatus.has(id) && this.lastStatus.get(id) !== status) {
        row.classList.remove("row-flash")
        void row.offsetWidth // restart the animation if it's already running
        row.classList.add("row-flash")
      }
      this.lastStatus.set(id, status)
    })
    this.firstPass = false
  }

  filter(rows) {
    const q = this.searchTarget.value.trim().toLowerCase()
    const team = this.teamTarget.value
    const status = this.statusFilterTarget.value
    rows.forEach((row) => {
      const show = (!q || row.dataset.name.includes(q)) && (!team || row.dataset.teamId === team) && (!status || row.dataset.statusId === status)
      row.hidden = !show
    })
    this.element.querySelectorAll("tbody[data-team-body]").forEach((body) => {
      const visible = [...body.querySelectorAll("tr.board-row")].filter((r) => !r.hidden).length
      const header = body.querySelector("tr[data-team-header]")
      header.hidden = visible === 0
      const count = header.querySelector("[data-team-count]")
      if (count) count.textContent = `${visible} ${visible === 1 ? "agent" : "agents"}`
    })
    const shown = rows.filter((r) => !r.hidden).length
    this.countTarget.textContent = `${shown} of ${rows.length} ${rows.length === 1 ? "agent" : "agents"}`
    this.emptyTarget.classList.toggle("d-none", shown > 0 || rows.length === 0)
  }

  sortGroups() {
    const mode = this.sortTarget.value
    const num = (v, fallback) => (v === "" || v === undefined ? fallback : Number(v))
    this.element.querySelectorAll("tbody[data-team-body]").forEach((body) => {
      const rows = [...body.querySelectorAll("tr.board-row")]
      let sorted
      if (mode === "time") {
        // longest in their current status first; agents with no data last
        sorted = rows.slice().sort((a, b) => (num(a.dataset.since, Infinity) - num(b.dataset.since, Infinity)) || a.dataset.name.localeCompare(b.dataset.name))
      } else if (mode === "status") {
        sorted = rows.slice().sort((a, b) => (num(a.dataset.statusOrder, 999) - num(b.dataset.statusOrder, 999)) || a.dataset.name.localeCompare(b.dataset.name))
      } else {
        sorted = rows.slice().sort((a, b) => a.dataset.name.localeCompare(b.dataset.name))
      }
      if (sorted.some((row, i) => row !== rows[i])) sorted.forEach((row) => body.appendChild(row))
    })
  }

  updateTotals(rows) {
    const counts = new Map()
    rows.filter((r) => !r.hidden && r.dataset.statusId).forEach((r) => counts.set(r.dataset.statusId, (counts.get(r.dataset.statusId) || 0) + 1))
    const ordered = Object.entries(this.statusesValue).sort((a, b) => a[1].order - b[1].order)
    this.totalsTarget.innerHTML = ordered.map(([id, s]) =>
      `<span class="me-3"><span class="badge rounded-pill" style="background-color:${s.color};color:${textColor(s.color)}">${counts.get(id) || 0} ${escapeHtml(s.name)}</span></span>`
    ).join("")
  }

  // --- the horizontal bars --------------------------------------------------------------------

  get now() { return Date.now() + this.serverOffset }

  drawBars(rows) {
    const now = this.now
    const lists = rows.map((r) => JSON.parse(r.dataset.events || "[]"))
    const axis = computeAxis(lists, this.dayStartValue, now, this.timeZoneValue)
    drawAxis(this.axisTarget, axis, this.timeZoneValue)
    const stamp = `${axis.start}|${axis.end}|${Math.floor(now / 30000)}`
    rows.forEach((row, i) => {
      const bar = row.querySelector(".board-bar")
      const signature = `${stamp}|${row.dataset.events}`
      if (bar.dataset.signature === signature) return
      bar.dataset.signature = signature
      bar.innerHTML = segmentsHtml(lists[i], axis, now, this.statusesValue, this.timeZoneValue)
    })
  }

  // --- connection badge -----------------------------------------------------------------------

  updateLive() {
    const sources = [...document.querySelectorAll("turbo-cable-stream-source")]
    const live = sources.length > 0 && sources.every((s) => s.hasAttribute("connected"))
    this.liveTarget.textContent = live ? "Live" : "Reconnecting…"
    this.liveTarget.classList.toggle("text-bg-success", live)
    this.liveTarget.classList.toggle("text-bg-secondary", !live)
  }
}
