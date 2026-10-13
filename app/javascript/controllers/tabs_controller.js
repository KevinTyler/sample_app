import { Controller } from "@hotwired/stimulus"

// Accessible tabs (WAI-ARIA tabs pattern): click or arrow keys switch panels.
export default class extends Controller {
  static targets = [ "tab", "panel" ]

  select(event) {
    this.show(this.tabTargets.indexOf(event.currentTarget))
  }

  keydown(event) {
    const keys = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }
    if (!(event.key in keys)) return
    event.preventDefault()
    const count = this.tabTargets.length
    const next = (this.tabTargets.indexOf(event.currentTarget) + keys[event.key] + count) % count
    this.show(next)
    this.tabTargets[next].focus()
  }

  show(index) {
    this.tabTargets.forEach((tab, i) => {
      const selected = i === index
      tab.setAttribute("aria-selected", String(selected))
      tab.tabIndex = selected ? 0 : -1
    })
    this.panelTargets.forEach((panel, i) => { panel.hidden = i !== index })
  }
}
