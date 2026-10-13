import { Controller } from "@hotwired/stimulus"

// Registers the service worker so hosts and door staff can install Cordially on their phones.
export default class extends Controller {
  connect() {
    if ("serviceWorker" in navigator && window.isSecureContext) {
      navigator.serviceWorker.register("/service-worker", { scope: "/" }).catch(() => {})
    }
  }
}
