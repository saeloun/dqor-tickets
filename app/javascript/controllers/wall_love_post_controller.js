import { Controller } from "@hotwired/stimulus"
import { loadWidgets, recordingIframe } from "wall_love/embed_widgets"

export default class extends Controller {
  static targets = ["embed", "button", "preview", "status"]
  static values = { postId: String, videoId: String }

  connect() {
    this.generation = 0
    this.onBeforeCache = () => this.clear()
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    this.clear()
  }

  disconnect() { document.removeEventListener("turbo:before-cache", this.onBeforeCache); this.clear() }

  deactivate(event) { if (event.target !== this.element) this.clear() }

  clear() {
    this.generation = (this.generation || 0) + 1
    this.embedTarget.replaceChildren()
    this.statusTarget.textContent = ""
    if (this.hasPreviewTarget) this.previewTarget.hidden = false
    if (this.hasButtonTarget) { this.buttonTarget.hidden = false; this.buttonTarget.disabled = false }
  }

  async load() {
    this.element.dispatchEvent(new Event("wall-love-media-activate", { bubbles: true }))
    this.clear()
    const generation = this.generation
    this.buttonTarget.disabled = true
    this.statusTarget.textContent = "Loading the original platform preview…"
    try {
      if (this.hasVideoIdValue && /^[A-Za-z0-9_-]{11}$/.test(this.videoIdValue)) {
        this.embedTarget.replaceChildren(recordingIframe(this.videoIdValue, this.element.querySelector(".wall-love-source__author").textContent))
        if (this.hasPreviewTarget) this.previewTarget.hidden = true
      } else if (this.hasPostIdValue && /^\d{15,24}$/.test(this.postIdValue)) {
        const widgets = await loadWidgets()
        if (generation !== this.generation || !this.element.isConnected || this.element.hidden) return
        const container = document.createElement("div")
        this.embedTarget.replaceChildren(container)
        const rendered = await widgets.createTweet(this.postIdValue, container, { dnt: true, conversation: "none", theme: document.documentElement.dataset.theme === "dark" ? "dark" : "light" })
        if (generation !== this.generation || !this.element.isConnected || this.element.hidden) { container.remove(); return }
        if (!rendered) throw new Error("Post unavailable")
      } else {
        throw new Error("Preview unavailable")
      }
      this.buttonTarget.hidden = true
      this.statusTarget.textContent = "Preview loaded. The original source link remains available below."
    } catch (_) {
      if (generation !== this.generation || !this.element.isConnected) return
      this.buttonTarget.disabled = false
      this.statusTarget.textContent = "This preview is unavailable. Open the original source below."
    }
  }
}
