import { Controller } from "@hotwired/stimulus"
import "html5-qrcode"

export default class extends Controller {
  static targets = ["reader", "result"]

  connect() {
    const Scanner = window.__Html5QrcodeLibrary__?.Html5QrcodeScanner
    if (!Scanner) return this.show("Scanner failed to load. Refresh and try again.")

    this.scanner = new Scanner(this.readerTarget.id, { fps: 10, qrbox: { width: 250, height: 250 } }, false)
    this.scanner.render(value => this.scan(value), () => {})
  }

  disconnect() {
    const scanner = this.scanner
    this.scanner = null
    scanner?.clear().catch(() => {})
  }

  scan(value) {
    if (this.navigating) return

    let url
    try {
      url = new URL(value, window.location.origin)
    } catch (_) {
      return this.show("That code is not an attendee profile.")
    }

    if (url.origin !== window.location.origin || !url.pathname.match(/^\/community\/\d+\/?$/)) {
      return this.show("That code is not an attendee profile from this event.")
    }

    this.navigating = true
    window.location.assign(url.href)
  }

  show(message) {
    this.resultTarget.textContent = message
    this.resultTarget.hidden = false
  }
}
