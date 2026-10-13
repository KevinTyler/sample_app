import { Controller } from "@hotwired/stimulus"

// Plays the envelope-opening reveal the first time a guest opens their invitation in this browser.
// Without JavaScript, with reduced motion, or on later visits the card is simply shown.
export default class extends Controller {
  static targets = ["envelope"]
  static values = { key: String }

  connect() {
    if (!this.hasEnvelopeTarget) return
    const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    if (reduced || this.seen()) {
      this.envelopeTarget.remove()
      return
    }
    this.element.classList.add("is-sealed")
    this.timer = setTimeout(() => this.open(), 900)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  open() {
    if (!this.element.classList.contains("is-sealed") || this.element.classList.contains("is-open")) return
    this.element.classList.add("is-open")
    this.remember()
    setTimeout(() => {
      this.element.classList.remove("is-sealed", "is-open")
      if (this.hasEnvelopeTarget) this.envelopeTarget.remove()
    }, 1700)
  }

  storageKey() {
    return `cordially:opened:${this.keyValue}`
  }

  seen() {
    try { return window.localStorage.getItem(this.storageKey()) === "1" } catch { return false }
  }

  remember() {
    try { window.localStorage.setItem(this.storageKey(), "1") } catch { /* private mode: ignore */ }
  }
}
