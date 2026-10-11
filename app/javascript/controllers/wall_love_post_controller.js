import { Controller } from "@hotwired/stimulus"
import { recordingIframe } from "wall_love/embed_widgets"

export default class extends Controller {
  static targets = ["embed", "button", "preview", "status"]
  static values = { videoId: String }

  connect() {
    this.onBeforeCache = () => this.clear()
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    this.clear()
  }

  disconnect() { document.removeEventListener("turbo:before-cache", this.onBeforeCache); this.clear() }

  deactivate(event) { if (event.target !== this.element) this.clear() }

  clear() {
    this.embedTarget.replaceChildren()
    this.statusTarget.textContent = ""
    if (this.hasPreviewTarget) this.previewTarget.hidden = false
    if (this.hasButtonTarget) { this.buttonTarget.hidden = false; this.buttonTarget.disabled = false }
  }

  load() {
    this.element.dispatchEvent(new Event("wall-love-media-activate", { bubbles: true }))
    this.clear()
    this.buttonTarget.disabled = true
    this.statusTarget.textContent = "Loading the original platform preview…"
    try {
      if (this.hasVideoIdValue && /^[A-Za-z0-9_-]{11}$/.test(this.videoIdValue)) {
        this.embedTarget.replaceChildren(recordingIframe(this.videoIdValue, this.element.querySelector(".wall-love-source__author").textContent))
        if (this.hasPreviewTarget) this.previewTarget.hidden = true
      } else {
        throw new Error("Preview unavailable")
      }
      this.buttonTarget.hidden = true
      this.statusTarget.textContent = "Preview loaded. The original source link remains available below."
    } catch (_) {
      this.buttonTarget.disabled = false
      this.statusTarget.textContent = "This preview is unavailable. Open the original source below."
    }
  }
}
