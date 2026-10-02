import { Controller } from "@hotwired/stimulus"
import "html5-qrcode"
export default class extends Controller {
  static values = { url: String }
  static targets = ["result"]
  connect() {
    const Scanner = window.__Html5QrcodeLibrary__?.Html5QrcodeScanner
    if (!Scanner) { this.resultTarget.textContent = "Camera scanner unavailable. Reload to retry."; return }
    this.scanner = new Scanner("slot-reader", { fps: 10, qrbox: { width: 250, height: 250 } }, false)
    this.scanner.render(secret => this.scan(secret), () => {})
  }
  disconnect() { this.abort?.abort(); this.scanner?.clear().catch(() => {}) }
  scan(secret) {
    if (this.busy || this.pending || secret === this.lastSecret) return
    this.lastSecret = secret
    this.pending = { secret, request_key: crypto.randomUUID() }
    this.submit()
  }
  next() { if (!this.busy && !this.pending) this.lastSecret = null }
  retry() { if (this.pending && !this.busy) this.submit() }
  async submit() {
    this.busy = true
    this.resultTarget.textContent = "Waiting for server confirmation…"
    this.abort = new AbortController()
    const timer = setTimeout(() => this.abort.abort(), 15000)
    try {
      const response = await fetch(this.urlValue, { method: "POST", signal: this.abort.signal, headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }, body: JSON.stringify(this.pending) })
      if (response.redirected || ![200, 422].includes(response.status)) throw new Error()
      const body = await response.json()
      if (!["success", "error"].includes(body.state) || !body.message) throw new Error()
      this.resultTarget.textContent = body.message
      this.pending = null
    } catch (_) { this.resultTarget.textContent = "Not confirmed. Check connection/session and retry the same scan safely." }
    finally { clearTimeout(timer); this.busy = false }
  }
}
