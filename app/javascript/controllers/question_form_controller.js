import { Controller } from "@hotwired/stimulus"

// Shows the "choices" box only for multiple-choice questions.
export default class extends Controller {
  static targets = ["kind", "options"]

  connect() { this.toggle() }

  toggle() {
    this.optionsTarget.hidden = this.kindTarget.value !== "choice"
  }
}
