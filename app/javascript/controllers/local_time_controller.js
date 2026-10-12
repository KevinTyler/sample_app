import { Controller } from "@hotwired/stimulus"

// Shows the event start time in the guest's own time zone when it differs from the event's.
export default class extends Controller {
  static values = { iso: String, zone: String }

  connect() {
    const viewerZone = Intl.DateTimeFormat().resolvedOptions().timeZone
    if (!this.isoValue || !viewerZone || viewerZone === this.zoneValue) return

    const date = new Date(this.isoValue)
    const formatted = new Intl.DateTimeFormat(undefined, {
      weekday: "long", month: "long", day: "numeric", hour: "numeric", minute: "2-digit", timeZoneName: "short"
    }).format(date)
    this.element.textContent = `That's ${formatted} where you are.`
    this.element.hidden = false
  }
}
