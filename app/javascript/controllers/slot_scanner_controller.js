import { Controller } from "@hotwired/stimulus"
import { initializeCamera, interruptCamera, restartCamera } from "scanning/camera"
export default class extends Controller {
  static values = { url: String }
  static targets = ["result", "cameraStatus", "control"]
  connect() { this.connected = true; this.busy = false; this.initializeScanner() }
  initializeScanner() { initializeCamera(this, "slot-reader", "Attendee lookup remains available.") }

  disconnect() { this.connected = false; this.abort?.abort(); this.scanner?.clear().catch(() => {}); this.scanner = null }
  beforeCache() { this.abort?.abort(); this.interruptCamera() }
  visibilityChanged() { if (document.hidden) this.interruptCamera() }
  interruptCamera() { interruptCamera(this, "Attendee lookup remains available.") }
  restartCamera() { return restartCamera(this, "Allow camera access and choose the back/rear camera. If access is denied, use attendee lookup below.") }

  manual(event) {
    if (this.busy || this.pending) return
    this.pending = { ticket_id: event.currentTarget.dataset.ticketId, request_key: crypto.randomUUID() }
    this.submit()
  }
  scan(secret) {
    if (this.busy || this.pending || document.hidden || this.cameraInterrupted || secret === this.lastSecret) return
    this.lastSecret = secret
    this.pending = { secret, request_key: crypto.randomUUID() }
    this.submit()
  }
  next() { if (!this.busy && !this.pending) this.lastSecret = null }
  retry() { if (this.pending && !this.busy) this.submit() }
  async submit() {
    this.busy = true
    this.controlTargets.forEach(control => { control.disabled = true })
    this.resultTarget.textContent = "Waiting for server confirmation…"
    this.abort = new AbortController()
    const timer = setTimeout(() => this.abort.abort(), 15000)
    try {
      const response = await fetch(this.urlValue, { method: "POST", signal: this.abort.signal, headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content ?? "" }, body: JSON.stringify(this.pending) })
      if (response.redirected || ![200, 422].includes(response.status)) throw new Error()
      const body = await response.json()
      if (!["success", "error"].includes(body.state) || !body.message) throw new Error()
      this.resultTarget.textContent = body.message
      this.pending = null
    } catch (_) { this.resultTarget.textContent = "Not confirmed. Check connection/session and retry the same scan safely." }
    finally { clearTimeout(timer); this.busy = false; if (this.connected) this.controlTargets.forEach(control => { control.disabled = false }) }
  }
}
