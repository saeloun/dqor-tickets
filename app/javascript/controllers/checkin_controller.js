import { Controller } from "@hotwired/stimulus"
import "html5-qrcode"

export default class extends Controller {
  static targets = ["date", "result"]

  connect() {
    const Scanner = window.__Html5QrcodeLibrary__?.Html5QrcodeScanner
    if (!Scanner) return this.show("error", "Scanner failed to load")

    this.scanner = new Scanner("checkin-reader", { fps: 10, qrbox: { width: 250, height: 250 } }, false)
    this.scanner.render(secret => this.scan(secret), () => {})
  }

  disconnect() {
    this.scanner?.clear().catch(() => {})
  }

  scanTicket(event) {
    this.scan(event.currentTarget.dataset.secret)
  }

  async scan(secret) {
    this.pauseScanner()
    try {
      const response = await fetch("/checkin", {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? ""
        },
        body: JSON.stringify({ secret, date: this.dateTarget.value })
      })
      const body = await response.json()
      this.show(body.state, body.message)
    } catch (_) {
      this.show("error", "Check-in failed. Try again.")
    } finally {
      window.setTimeout(() => this.resumeScanner(), 1200)
    }
  }

  pauseScanner() {
    try {
      this.scanner?.pause(true)
    } catch (_) {
    }
  }

  resumeScanner() {
    try {
      this.scanner?.resume()
    } catch (_) {
    }
  }

  show(state, message) {
    this.resultTarget.className = `checkin-result checkin-result--${state}`
    this.resultTarget.textContent = message
    this.resultTarget.hidden = false
  }
}
