import { Controller } from "@hotwired/stimulus"

// A file drop target that submits its form as soon as a file is dropped or picked.
export default class extends Controller {
  static targets = ["input", "label"]

  connect() {
    this.depth = 0
  }

  enter(event) {
    event.preventDefault()
    this.depth++
    this.element.classList.add("is-over")
  }

  leave() {
    this.depth = Math.max(0, this.depth - 1)
    if (this.depth === 0) this.element.classList.remove("is-over")
  }

  over(event) {
    event.preventDefault()
  }

  drop(event) {
    this.depth = 0
    this.element.classList.remove("is-over")
    if (!event.dataTransfer?.files?.length || event.target === this.inputTarget) return

    event.preventDefault()
    this.inputTarget.files = event.dataTransfer.files
    this.submit()
  }

  submit() {
    if (!this.inputTarget.files.length) return
    if (this.hasLabelTarget) this.labelTarget.textContent = `Reading ${this.inputTarget.files[0].name}…`
    this.element.closest("form").requestSubmit()
  }
}
