import { Controller } from "@hotwired/stimulus"

// Status form: keeps the color picker and hex box in sync, shows a live preview pill,
// and (on a new status) ticks the Productive / Counts toward CFT boxes to match the category.
export default class extends Controller {
  static targets = ["name", "picker", "hex", "pill", "category", "productive", "cft"]
  static values = { productive: Array, cft: Array, applyDefaults: Boolean }

  connect() { this.refresh() }

  pickerChanged() { this.hexTarget.value = this.pickerTarget.value; this.refresh() }

  hexChanged() {
    if (/^#[0-9a-fA-F]{6}$/.test(this.hexTarget.value)) this.pickerTarget.value = this.hexTarget.value
    this.refresh()
  }

  categoryChanged() {
    if (this.applyDefaultsValue) {
      this.productiveTarget.checked = this.productiveValue.includes(this.categoryTarget.value)
      this.cftTarget.checked = this.cftValue.includes(this.categoryTarget.value)
    }
  }

  refresh() {
    const hex = /^#[0-9a-fA-F]{6}$/.test(this.hexTarget.value) ? this.hexTarget.value : "#6c757d"
    const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16))
    this.pillTarget.style.backgroundColor = hex
    this.pillTarget.style.color = (r * 299 + g * 587 + b * 114) / 1000 >= 150 ? "#212529" : "#ffffff"
    this.pillTarget.textContent = this.nameTarget.value || "Status name"
  }
}
