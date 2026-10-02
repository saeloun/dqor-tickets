import { Controller } from "@hotwired/stimulus"
import { initializeCamera, interruptCamera, restartCamera } from "scanning/camera"

export default class extends Controller {
  static targets = ["cameraStatus", "result", "manual"]
  static values = { sample: String }

  connect() { this.connected = true; this.initializeScanner() }
  initializeScanner() { initializeCamera(this, "rehearsal-reader", "Use the synthetic manual test below.") }
  visibilityChanged() { if (document.hidden) this.interruptCamera() }
  interruptCamera() { interruptCamera(this, "The synthetic manual test remains available.") }
  restartCamera() {
    return restartCamera(this, "Tap Request Camera Permissions and choose the back/rear camera. If denied, allow access in browser settings or use the synthetic manual test below.")
  }
  disconnect() { this.connected = false; this.scanner?.clear().catch(() => {}); this.scanner = null }
  beforeCache() { this.interruptCamera(); this.resultTarget.textContent = "No test result yet." }
  scan(value) {
    if (!this.connected || document.hidden || this.cameraInterrupted) return
    this.report(value, "QR decoder")
  }
  manualTest() { this.report(this.manualTarget.value.trim(), "Manual fallback (camera not tested)") }
  report(value, source) {
    this.resultTarget.textContent = value === this.sampleValue
      ? `SELF-TEST ONLY: ${source} recognized the synthetic sample. Nobody was admitted; nothing was redeemed.`
      : "SELF-TEST ONLY: Unrecognized sample. Use the test QR or test text shown here. No ticket lookup or admission was attempted."
  }
}
