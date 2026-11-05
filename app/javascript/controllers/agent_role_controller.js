import { Controller } from "@hotwired/stimulus"

// Only agents belong to a team, so hide the team picker for other roles.
export default class extends Controller {
  static targets = ["team"]

  connect() { this.toggle() }

  toggle() {
    const role = this.element.querySelector("select[name='user[role]']")
    this.teamTarget.hidden = role.value !== "agent"
  }
}
