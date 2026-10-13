import { Controller } from "@hotwired/stimulus"

// Party size on the reply form: adult/kid steppers (kept within the invitation's limit) and
// one name field per extra person. Works without JS as plain number inputs.
export default class extends Controller {
  static targets = [ "adults", "kids", "size", "name", "namesField" ]
  static values = { max: Number }

  connect() { this.update() }

  step({ params: { field, delta } }) {
    const input = field === "adults" ? this.adultsTarget : this.kidsTarget
    const min = field === "adults" ? 1 : 0
    const next = Math.max(min, (parseInt(input.value, 10) || 0) + delta)
    if (this.totalWith(field, next) > this.maxValue) return
    input.value = next
    this.update()
  }

  totalWith(field, value) {
    const adults = field === "adults" ? value : this.read(this.adultsTarget)
    const kids = field === "kids" ? value : this.read(this.kidsTarget)
    return adults + kids
  }

  read(input) {
    return parseInt(input?.value, 10) || 0
  }

  total() {
    if (this.hasAdultsTarget) return this.read(this.adultsTarget) + this.read(this.kidsTarget)
    if (this.hasSizeTarget) return this.read(this.sizeTarget)
    return 1
  }

  update() {
    const extra = Math.max(0, this.total() - 1)
    this.nameTargets.forEach((input, i) => { input.hidden = i >= extra })
    if (this.hasNamesFieldTarget) this.namesFieldTarget.hidden = extra === 0
  }
}
