import { Controller } from "@hotwired/stimulus"

// Row checkboxes + "select all" for the guest list's bulk-action bar.
export default class extends Controller {
  static targets = ["checkbox", "all", "count", "submit", "action", "group", "bar"]

  connect() { this.update() }

  toggleAll() {
    this.checkboxTargets.forEach((box) => { box.checked = this.allTarget.checked })
    this.update()
  }

  actionChanged() {
    if (this.hasGroupTarget) this.groupTarget.hidden = this.actionTarget.value !== "group"
    this.update()
  }

  update() {
    const selected = this.checkboxTargets.filter((box) => box.checked).length
    if (this.hasCountTarget) this.countTarget.textContent = `${selected} selected`
    if (this.hasAllTarget) {
      this.allTarget.checked = selected > 0 && selected === this.checkboxTargets.length
      this.allTarget.indeterminate = selected > 0 && selected < this.checkboxTargets.length
    }
    if (this.hasSubmitTarget) this.submitTarget.disabled = selected === 0 || !this.actionTarget.value
    if (this.hasBarTarget) this.barTarget.classList.toggle("is-active", selected > 0)
  }
}
