import { Controller } from "@hotwired/stimulus"

// Hides party size and "attending only" questions when the guest declines.
export default class extends Controller {
  static targets = ["attendingOnly"]

  connect() { this.update() }

  update() {
    const checked = this.element.querySelector("input[type=radio][name='rsvp[status]']:checked")
    const declining = checked && checked.value === "no"
    this.attendingOnlyTargets.forEach((el) => { el.hidden = declining })
  }
}
