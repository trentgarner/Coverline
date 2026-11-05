import { Controller } from "@hotwired/stimulus"

// Live "time in status" timers. Put this on any container; every [data-elapsed-since] inside
// (a timestamp in ms) counts up once a second, even for rows that arrive later over Turbo Streams.
// Uses the server's clock (not the laptop's) so a wrong clock can't show a wrong time.
// An element with data-limit-seconds turns yellow past the limit and red past 1.5x the limit.
export default class extends Controller {
  static values = { serverNow: Number }

  connect() {
    this.loadedAt = Date.now()
    this.tick()
    this.timer = setInterval(() => this.tick(), 1000)
  }

  disconnect() { clearInterval(this.timer) }

  get offset() { return this.serverNowValue ? this.serverNowValue - this.loadedAt : 0 }

  tick() {
    const now = Date.now() + this.offset
    this.element.querySelectorAll("[data-elapsed-since]").forEach((el) => {
      const since = Number(el.dataset.elapsedSince)
      if (!since) return
      const secs = Math.max(0, Math.floor((now - since) / 1000))
      const text = format(secs)
      if (el.textContent !== text) el.textContent = text
      const limit = Number(el.dataset.limitSeconds) || 0
      el.classList.toggle("elapsed-over", limit > 0 && secs >= limit * 1.5)
      el.classList.toggle("elapsed-warn", limit > 0 && secs >= limit && secs < limit * 1.5)
    })
  }
}

function format(total) {
  const h = Math.floor(total / 3600)
  const m = Math.floor((total % 3600) / 60)
  const s = total % 60
  const pad = (n) => String(n).padStart(2, "0")
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`
}
