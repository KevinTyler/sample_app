import { Controller } from "@hotwired/stimulus"

// Copies a guest's personal link. Falls back to selecting the text if the Clipboard API is unavailable.
export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    const text = this.sourceTarget.value
    try {
      await navigator.clipboard.writeText(text)
      this.flash("Copied!")
    } catch {
      this.sourceTarget.select()
      this.flash("Press Ctrl+C")
    }
  }

  flash(label) {
    if (!this.hasButtonTarget) return
    const original = this.buttonTarget.dataset.label || this.buttonTarget.textContent
    this.buttonTarget.dataset.label = original
    this.buttonTarget.textContent = label
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { this.buttonTarget.textContent = original }, 1800)
  }
}
