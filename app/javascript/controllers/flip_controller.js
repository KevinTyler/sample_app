import { Controller } from "@hotwired/stimulus"

// Turns the card over to its back. Without JavaScript the back simply follows the front.
export default class extends Controller {
  static targets = [ "inner", "front", "back", "button", "label" ]
  static values = { frontLabel: { type: String, default: "Flip for the details" }, backLabel: { type: String, default: "Back to the front" } }

  connect() {
    this.element.classList.add("is-ready")
    this.buttonTarget.hidden = false
    this.render(false)
  }

  toggle() {
    this.render(!this.element.classList.contains("is-flipped"))
  }

  render(flipped) {
    this.element.classList.toggle("is-flipped", flipped)
    this.buttonTarget.setAttribute("aria-pressed", String(flipped))
    this.labelTarget.textContent = flipped ? this.backLabelValue : this.frontLabelValue
    this.frontTarget.inert = flipped
    this.backTarget.inert = !flipped
  }
}
