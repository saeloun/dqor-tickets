import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["freshness"]
  connect() {
    this.stale = () => { this.freshnessTarget.textContent = navigator.onLine ? "Snapshot may be stale. Refresh to verify current status." : "Offline — displayed status may be stale. Reconnect and refresh." }
    window.addEventListener("offline", this.stale)
    window.addEventListener("online", this.stale)
    document.addEventListener("visibilitychange", this.stale)
    this.timer = setTimeout(this.stale, 30000)
    if (!navigator.onLine) this.stale()
  }
  disconnect() {
    clearTimeout(this.timer)
    window.removeEventListener("offline", this.stale)
    window.removeEventListener("online", this.stale)
    document.removeEventListener("visibilitychange", this.stale)
  }
}
