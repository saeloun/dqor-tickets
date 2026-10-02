import { Controller } from "@hotwired/stimulus"
import "html5-qrcode"
export default class extends Controller {
  static values = { url: String }
  static targets = ["result", "cameraStatus", "control"]
  connect() { this.connected = true; this.busy = false; this.initializeScanner() }
  initializeScanner() {
    this.cameraInterrupted = false
    const Scanner = window.__Html5QrcodeLibrary__?.Html5QrcodeScanner
    if (!Scanner) { this.cameraStatusTarget.textContent = "Camera scanner unavailable. Use attendee lookup below."; return }
    if (!window.isSecureContext) { this.cameraStatusTarget.textContent = "Camera requires HTTPS. Use attendee lookup below."; return }
    this.scanner = new Scanner("slot-reader", {
      fps: 10, rememberLastUsedCamera: false, useBarCodeDetectorIfSupported: false,
      qrbox: (width, height) => { const side = Math.min(250, Math.floor(Math.min(width, height) * 0.7)); return { width: side, height: side } }
    }, false)
    this.scanner.render(secret => this.scan(secret), () => {})
  }
  disconnect() { this.connected = false; this.abort?.abort(); this.scanner?.clear().catch(() => {}); this.scanner = null }
  beforeCache() { this.abort?.abort(); this.interruptCamera() }
  visibilityChanged() { if (document.hidden) this.interruptCamera() }
  interruptCamera() {
    this.cameraInterrupted = true
    try { this.scanner?.pause(true) } catch (_) {}
    this.cameraStatusTarget.textContent = "Camera paused after leaving the page or rotating your phone. Tap Restart camera, then choose the back/rear camera. Attendee lookup remains available."
  }
  async restartCamera() {
    if (this.busy) return
    try { await this.scanner?.clear() } catch (_) {}
    if (!this.connected) return
    this.scanner = null
    this.cameraStatusTarget.textContent = "Allow camera access and choose the back/rear camera. If access is denied, use attendee lookup below."
    this.initializeScanner()
  }
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
