import { Controller } from "@hotwired/stimulus"

// Turns the card over to its back. Without JavaScript the back simply follows the front.
export default class extends Controller {
  static targets = [ "inner", "front", "back", "button", "label" ]

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
    this.labelTarget.textContent = flipped ? "Back to the front" : "Flip for the details"
    this.frontTarget.inert = flipped
    this.backTarget.inert = !flipped
  }
}
