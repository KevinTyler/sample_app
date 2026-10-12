import { Controller } from "@hotwired/stimulus"

// Shows how many guests the message will reach as the host changes filters and channels.
export default class extends Controller {
  static targets = ["output"]
  static values = { url: String }

  connect() { this.refresh() }

  async refresh() {
    const params = new URLSearchParams()
    for (const [key, value] of new FormData(this.element)) {
      if (key.startsWith("message[audience]") || key.startsWith("message[channels]") || key === "message[kind]") params.append(key, value)
    }
    try {
      const response = await fetch(`${this.urlValue}?${params}`, { headers: { Accept: "application/json" } })
      if (!response.ok) return
      const { reachable, unreachable } = await response.json()
      let text = `This will reach ${reachable} ${reachable === 1 ? "guest" : "guests"}.`
      if (unreachable > 0) text += ` ${unreachable} matching ${unreachable === 1 ? "guest has" : "guests have"} no way to receive it on the chosen channels (or haven't been invited yet).`
      this.outputTarget.textContent = text
    } catch {
      // Leave the default explanation in place.
    }
  }
}
