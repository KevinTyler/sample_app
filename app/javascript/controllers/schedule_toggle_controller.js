import { Controller } from "@hotwired/stimulus"

// Shows the date/time field only when "Schedule" is chosen.
export default class extends Controller {
  static targets = ["when"]

  connect() { this.update() }

  update() {
    const later = this.element.querySelector("input[name='send_at'][value='later']")
    this.whenTarget.hidden = !later?.checked
  }
}
