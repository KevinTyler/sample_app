import { Controller } from "@hotwired/stimulus"

// Scans a guest's door pass with the device camera where the browser supports BarcodeDetector.
// Only same-origin check-in links are followed; anything else is ignored.
export default class extends Controller {
  static targets = [ "dialog", "video", "status" ]

  async open(event) {
    event.preventDefault()
    this.dialogTarget.showModal()
    if (!("BarcodeDetector" in window) || !navigator.mediaDevices?.getUserMedia) {
      this.statusTarget.textContent = "This browser can't scan here. Open your phone's camera app and point it at the pass instead — it opens the guest's check-in page."
      return
    }
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" }, audio: false })
      this.videoTarget.srcObject = this.stream
      await this.videoTarget.play()
      this.detector = new window.BarcodeDetector({ formats: [ "qr_code" ] })
      this.statusTarget.textContent = "Point the camera at the guest's pass."
      this.tick()
    } catch (_error) {
      this.statusTarget.textContent = "Camera unavailable. Allow camera access, or use your phone's camera app."
    }
  }

  async tick() {
    if (!this.stream) return
    try {
      const codes = await this.detector.detect(this.videoTarget)
      for (const code of codes) {
        const url = new URL(code.rawValue, window.location.href)
        if (url.origin === window.location.origin && url.pathname.endsWith("/check-in/scan")) {
          this.close()
          window.Turbo ? window.Turbo.visit(url.toString()) : (window.location.href = url.toString())
          return
        }
      }
    } catch (_error) {
      // Not a URL or frame not ready: keep scanning.
    }
    this.frame = requestAnimationFrame(() => this.tick())
  }

  close() {
    cancelAnimationFrame(this.frame)
    this.stream?.getTracks().forEach((track) => track.stop())
    this.stream = null
    if (this.dialogTarget.open) this.dialogTarget.close()
  }

  disconnect() {
    this.close()
  }
}
