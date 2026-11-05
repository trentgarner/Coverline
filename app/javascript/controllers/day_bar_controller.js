import { Controller } from "@hotwired/stimulus"
import { computeAxis, drawAxis, segmentsHtml } from "controllers/timeline_bar"

// One agent's horizontal bar for today (the agent page). Redraws when the page is refreshed
// by a live update, and every 30 seconds so the "now" line keeps moving.
export default class extends Controller {
  static targets = ["axis", "bar"]
  static values = { events: Array, statuses: Object, timeZone: String, dayStart: Number, serverNow: Number }

  connect() {
    this.loadedAt = Date.now()
    this.draw()
    this.timer = setInterval(() => this.draw(), 30000)
  }

  disconnect() { clearInterval(this.timer) }

  eventsValueChanged() { if (this.loadedAt) this.draw() }

  draw() {
    const now = Date.now() + (this.serverNowValue ? this.serverNowValue - this.loadedAt : 0)
    const axis = computeAxis([ this.eventsValue ], this.dayStartValue, now, this.timeZoneValue)
    drawAxis(this.axisTarget, axis, this.timeZoneValue)
    this.barTarget.innerHTML = segmentsHtml(this.eventsValue, axis, now, this.statusesValue, this.timeZoneValue)
  }
}
