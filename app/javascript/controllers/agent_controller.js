import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// The conversation with Cordially on the web: send with Enter, attach or drop a file (sent right
// away), quick-reply chips, and wait for the agent's answer by polling for new messages.
export default class extends Controller {
  static targets = ["thread", "form", "input", "file", "fileLabel", "send", "drop", "thinkingText"]
  static values = { pollUrl: String, waiting: Boolean }

  connect() {
    this.dragDepth = 0
    this.scrollToEnd(false)
    this.grow()
    if (this.waitingValue) this.poll()
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  keydown(event) {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault()
      this.submit()
    }
  }

  grow() {
    if (!this.hasInputTarget) return
    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${Math.min(this.inputTarget.scrollHeight, 200)}px`
  }

  chip(event) {
    this.inputTarget.value = event.currentTarget.dataset.text
    this.submit()
  }

  filePicked() {
    const file = this.fileTarget.files[0]
    if (!file) return
    this.fileLabelTarget.textContent = `Sending ${file.name}…`
    this.fileLabelTarget.classList.add("is-visible")
    this.submit()
  }

  submit() {
    if (!this.inputTarget.value.trim() && !this.fileTarget.files.length) return
    this.formTarget.requestSubmit()
  }

  sending() {
    this.sendTarget.disabled = true
  }

  sent(event) {
    this.sendTarget.disabled = false
    if (!event.detail.success) return
    this.formTarget.reset()
    this.fileLabelTarget.classList.remove("is-visible")
    this.fileLabelTarget.textContent = ""
    this.grow()
    this.startedAt = Date.now()
    this.poll()
    requestAnimationFrame(() => this.scrollToEnd(true))
  }

  // --- Waiting for the reply ---------------------------------------------------------------

  poll() {
    clearTimeout(this.timer)
    this.startedAt ||= Date.now()
    this.timer = setTimeout(() => this.fetchNew(), 1200)
  }

  async fetchNew() {
    const last = Math.max(0, ...[...this.threadTarget.querySelectorAll("[data-message-id]")].map((el) => Number(el.dataset.messageId)))
    try {
      const response = await fetch(`${this.pollUrlValue}?after=${last}`, { headers: { Accept: "text/vnd.turbo-stream.html" } })
      if (response.ok) {
        const before = this.threadTarget.childElementCount
        Turbo.renderStreamMessage(await response.text())
        await new Promise((resolve) => requestAnimationFrame(resolve))
        if (this.threadTarget.childElementCount !== before) this.scrollToEnd(true)
      }
    } catch (_error) {
      // Network blip: try again on the next tick.
    }
    if (!document.getElementById("agent-thinking")) {
      this.startedAt = null
      return
    }
    if (Date.now() - this.startedAt > 180_000) {
      if (this.hasThinkingTextTarget) this.thinkingTextTarget.textContent = "Still working on it — this page will catch up when you refresh."
      return
    }
    this.timer = setTimeout(() => this.fetchNew(), 1500)
  }

  // Brings the newest message into view just above the composer (which stays pinned to the
  // bottom of the screen while the conversation scrolls).
  scrollToEnd(smooth) {
    const threadBottom = this.threadTarget.getBoundingClientRect().bottom + window.scrollY
    const top = threadBottom + this.formTarget.offsetHeight + 12 - window.innerHeight
    window.scrollTo({ top: Math.max(0, top), behavior: smooth ? "smooth" : "auto" })
  }

  // --- Drop a file anywhere on the page ----------------------------------------------------

  dragEnter(event) {
    if (!this.hasFiles(event)) return
    this.dragDepth++
    this.dropTarget.classList.add("is-visible")
  }

  dragOver(event) {
    if (this.hasFiles(event)) event.preventDefault()
  }

  dragLeave() {
    this.dragDepth = Math.max(0, this.dragDepth - 1)
    if (this.dragDepth === 0) this.dropTarget.classList.remove("is-visible")
  }

  drop(event) {
    this.dragDepth = 0
    this.dropTarget.classList.remove("is-visible")
    if (!this.hasFiles(event)) return
    event.preventDefault()
    this.fileTarget.files = event.dataTransfer.files
    this.filePicked()
  }

  hasFiles(event) {
    return [...(event.dataTransfer?.types || [])].includes("Files")
  }
}
