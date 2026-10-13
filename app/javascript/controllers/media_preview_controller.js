import { Controller } from "@hotwired/stimulus"

// Shows the photo or video a kid just recorded before it's uploaded. Only one capture input
// keeps its file, so choosing a new one clears the others.
export default class extends Controller {
  static targets = [ "stage", "current" ]

  show(event) {
    const input = event.target
    const file = input.files?.[0]
    if (!file) return
    this.element.querySelectorAll("input[type=file][data-capture]").forEach((other) => {
      if (other !== input) other.value = ""
    })
    if (this.url) URL.revokeObjectURL(this.url)
    this.url = URL.createObjectURL(file)
    const media = file.type.startsWith("video/") ? document.createElement("video") : document.createElement("img")
    media.src = this.url
    if (media.tagName === "VIDEO") { media.controls = true; media.playsInline = true; media.muted = false }
    else media.alt = "Preview of the new photo"
    this.stageTarget.replaceChildren(media)
  }

  disconnect() {
    if (this.url) URL.revokeObjectURL(this.url)
  }
}
