import { Controller } from "@hotwired/stimulus"

// "Generate" button next to a password field: fills in a random temporary password
// (no look-alike characters) and shows it so the admin can pass it on.
export default class extends Controller {
  static targets = ["input"]

  generate() {
    const chars = "abcdefghjkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789"
    const bytes = crypto.getRandomValues(new Uint32Array(10))
    this.inputTarget.value = Array.from(bytes, (n) => chars[n % chars.length]).join("")
    this.inputTarget.type = "text"
  }
}
