import { Controller } from "@hotwired/stimulus"

// Submits the form when one of its fields changes (the visible submit button stays for no-JS use).
export default class extends Controller {
  submit() {
    this.element.requestSubmit()
  }
}
