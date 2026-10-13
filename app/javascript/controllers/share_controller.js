import { Controller } from "@hotwired/stimulus"

// Reveals a "More" button that opens the device share sheet (Web Share API) where supported.
export default class extends Controller {
  static targets = [ "native" ]
  static values = { title: String, text: String, url: String }

  connect() {
    if (navigator.share && this.hasNativeTarget) this.nativeTarget.hidden = false
  }

  async open() {
    try {
      await navigator.share({ title: this.titleValue, text: this.textValue, url: this.urlValue })
    } catch (_error) {
      // Dismissed or unsupported: nothing to do.
    }
  }
}
