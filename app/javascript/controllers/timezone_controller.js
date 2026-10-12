import { Controller } from "@hotwired/stimulus"

// On the new-event form, preselect the host's own time zone (from the browser) when we know it.
export default class extends Controller {
  static targets = ["select"]

  connect() {
    if (!this.hasSelectTarget || this.selectTarget.dataset.newRecord !== "true") return
    const zone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (zone && [...this.selectTarget.options].some((o) => o.value === zone)) {
      this.selectTarget.value = zone
    }
  }
}
