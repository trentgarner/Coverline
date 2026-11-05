import { Controller } from "@hotwired/stimulus"

// Drag rows to reorder, then save the new order to the server (plain HTML5 drag and drop).
export default class extends Controller {
  static targets = ["row"]
  static values = { url: String }

  dragStart(event) {
    this.dragging = event.currentTarget
    event.dataTransfer.effectAllowed = "move"
    this.dragging.classList.add("opacity-50")
  }

  dragOver(event) {
    event.preventDefault()
    const over = event.currentTarget
    if (!this.dragging || over === this.dragging) return
    const after = event.clientY > over.getBoundingClientRect().top + over.offsetHeight / 2
    over.parentNode.insertBefore(this.dragging, after ? over.nextSibling : over)
  }

  async dragEnd() {
    this.dragging?.classList.remove("opacity-50")
    this.dragging = null
    const ids = this.rowTargets.map((row) => row.dataset.id)
    const token = document.querySelector("meta[name=csrf-token]")?.content
    const body = new URLSearchParams()
    ids.forEach((id) => body.append("ids[]", id))
    const response = await fetch(this.urlValue, { method: "PATCH", headers: { "X-CSRF-Token": token, Accept: "text/plain" }, body })
    this.element.dispatchEvent(new CustomEvent("sortable:saved", { bubbles: true, detail: { ok: response.ok } }))
    if (!response.ok) window.location.reload()
  }
}
