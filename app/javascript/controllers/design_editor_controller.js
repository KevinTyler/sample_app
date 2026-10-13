import { Controller } from "@hotwired/stimulus"

// Live preview for the invitation design editor. Everything here only changes the on-screen
// preview (via the CSSOM, which our Content-Security-Policy permits); the server re-validates
// every value on save.
const LAYOUTS = ["centered", "left", "framed", "split"]
const PHOTO_STYLES = ["banner", "background", "inset"]
const HEX = /^#[0-9a-f]{6}$/i

export default class extends Controller {
  static targets = ["card", "headline", "tagline", "message", "frame", "contrast", "viewportButton", "envelope", "stamp"]
  static values = { templates: Object, fonts: Object }

  connect() {
    this.refresh()
  }

  disconnect() {
    if (this.photoUrl) URL.revokeObjectURL(this.photoUrl)
  }

  // --- Form helpers ---------------------------------------------------------

  inputs(name) {
    return [...this.element.querySelectorAll(`[name="design[${name}]"]`)]
  }

  read(name) {
    const fields = this.inputs(name)
    const radio = fields.find((f) => f.type === "radio" && f.checked)
    if (radio) return radio.value
    const checkbox = fields.find((f) => f.type === "checkbox")
    if (checkbox) return checkbox.checked
    return fields.find((f) => f.type !== "hidden")?.value ?? fields[0]?.value
  }

  write(name, value) {
    this.inputs(name).forEach((field) => {
      if (field.type === "radio") field.checked = field.value === value
      else if (field.type === "checkbox") field.checked = Boolean(value)
      else if (field.type !== "hidden") field.value = value ?? ""
    })
  }

  // --- Actions --------------------------------------------------------------

  chooseTemplate(event) {
    const template = this.templatesValue[event.target.value]
    if (!template) return

    for (const name of ["background_color", "text_color", "accent_color", "heading_font", "body_font", "layout", "headline", "tagline"]) {
      this.write(name, template[name])
    }
    this.write("show_artwork", Boolean(template.artwork))
    this.refresh()
  }

  applyPalette(event) {
    const { bg, ink, accent } = event.currentTarget.dataset
    this.write("background_color", bg)
    this.write("text_color", ink)
    this.write("accent_color", accent)
    this.refresh()
  }

  setViewport(event) {
    const viewport = event.currentTarget.dataset.viewport
    this.frameTarget.dataset.viewport = viewport
    this.viewportButtonTargets.forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.viewport === viewport))
    })
  }

  previewPhoto(event) {
    const file = event.target.files?.[0]
    if (!file) return
    if (this.photoUrl) URL.revokeObjectURL(this.photoUrl)
    this.photoUrl = URL.createObjectURL(file)
    this.refresh()
  }

  refresh() {
    const card = this.cardTarget
    const colors = {
      "--card-bg": this.read("background_color"),
      "--card-ink": this.read("text_color"),
      "--card-accent": this.read("accent_color")
    }
    for (const [property, value] of Object.entries(colors)) {
      if (HEX.test(value || "")) card.style.setProperty(property, value)
    }
    const accent = HEX.test(colors["--card-accent"] || "") ? colors["--card-accent"] : null
    const backdropHex = this.checkedHex("backdrop")
    if (backdropHex) this.element.style.setProperty("--studio-backdrop", backdropHex)
    else if (accent) this.element.style.setProperty("--studio-backdrop", `color-mix(in srgb, ${accent} 16%, #f3efe8)`)
    this.renderEnvelope(accent)

    const headingFont = this.read("heading_font")
    const bodyFont = this.read("body_font")
    if (this.fontsValue[headingFont]) card.style.setProperty("--card-heading-font", this.fontsValue[headingFont])
    if (this.fontsValue[bodyFont]) card.style.setProperty("--card-body-font", this.fontsValue[bodyFont])
    card.dataset.headingFont = headingFont

    const layout = this.read("layout")
    LAYOUTS.forEach((l) => card.classList.toggle(`invite-card--${l}`, l === layout))

    this.setText(this.headlineTarget, this.read("headline"))
    this.setText(this.taglineTarget, this.read("tagline"))
    this.setText(this.messageTarget, this.read("message"))

    this.renderArtwork()
    this.renderPhoto()
    this.checkContrast(colors["--card-bg"], colors["--card-ink"])
  }

  // --- Rendering ------------------------------------------------------------

  checkedHex(name) {
    const field = this.inputs(name).find((f) => f.checked)
    const hex = field?.dataset.hex
    return HEX.test(hex || "") ? hex : null
  }

  renderEnvelope(accent) {
    if (!this.hasEnvelopeTarget) return
    const envelope = this.envelopeTarget
    if (accent) envelope.style.setProperty("--card-accent", accent)
    const envelopeField = this.inputs("envelope").find((f) => f.checked)
    if (envelopeField) envelope.dataset.tone = envelopeField.dataset.tone || "light"
    const envelopeHex = this.checkedHex("envelope")
    if (envelopeHex) envelope.style.setProperty("--envelope", envelopeHex)
    else envelope.style.removeProperty("--envelope")
    const liner = this.read("liner")
    if (liner) envelope.dataset.liner = liner
    const stamp = this.read("stamp")
    if (this.hasStampTarget && stamp !== this.stampTarget.dataset.current) {
      const source = document.querySelector(`template[data-stamp-template="${stamp}"]`)
      this.stampTarget.replaceChildren(...(source ? [source.content.cloneNode(true)] : []))
      this.stampTarget.dataset.current = stamp
    }
  }

  setText(element, value) {
    element.textContent = value || ""
    element.hidden = !value
  }

  renderArtwork() {
    const card = this.cardTarget
    const template = this.templatesValue[this.read("template")]
    const artwork = this.read("show_artwork") ? template?.artwork : null
    let art = card.querySelector(":scope > .invite-art")

    if (!artwork) {
      art?.remove()
      return
    }
    if (art?.dataset.artwork === artwork) return

    const source = document.querySelector(`template[data-artwork-template="${artwork}"]`)
    if (!source) return
    art?.remove()
    art = document.createElement("div")
    art.className = `invite-art invite-art--${artwork}`
    art.dataset.artwork = artwork
    art.setAttribute("aria-hidden", "true")
    art.append(source.content.cloneNode(true))
    card.prepend(art)
  }

  renderPhoto() {
    const card = this.cardTarget
    const existing = card.querySelector(".invite-card__photo img")
    const src = this.photoUrl || existing?.getAttribute("src")
    const removing = this.element.querySelector("#remove_artwork")?.checked && !this.photoUrl
    card.querySelectorAll(".invite-card__photo").forEach((figure) => figure.remove())
    if (!src || removing) return

    const style = this.read("photo_style")
    const figure = document.createElement("figure")
    const variant = this.read("layout") === "split" && style !== "background" ? "banner" : style
    figure.className = `invite-card__photo invite-card__photo--${PHOTO_STYLES.includes(variant) ? variant : "banner"}`
    const img = document.createElement("img")
    img.src = src
    img.alt = ""
    figure.append(img)

    if (style === "background") {
      card.querySelector(":scope > .invite-art") ? card.querySelector(":scope > .invite-art").after(figure) : card.prepend(figure)
    } else {
      card.querySelector(".invite-card__inner").prepend(figure)
    }
  }

  checkContrast(background, text) {
    if (!this.hasContrastTarget || !HEX.test(background || "") || !HEX.test(text || "")) return
    this.contrastTarget.hidden = contrastRatio(background, text) >= 3
  }
}

function luminance(hex) {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255)
    .map((c) => (c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4))
  return 0.2126 * r + 0.7152 * g + 0.0722 * b
}

function contrastRatio(a, b) {
  const [la, lb] = [luminance(a), luminance(b)]
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
}
