import { Controller } from "@hotwired/stimulus"
import { recordingIframe } from "wall_love/embed_widgets"

export default class extends Controller {
  static targets = ["slide", "controls", "counter", "toggle", "status"]

  connect() {
    this.index = 0
    this.onBeforeCache = () => {
      this.pause()
      this.slideTargets.forEach(slide => { this.clearMedia(slide); slide.hidden = false })
      this.controlsTarget.hidden = true
      delete this.element.dataset.enhanced
    }
    document.addEventListener("turbo:before-cache", this.onBeforeCache)
    this.motion = window.matchMedia("(prefers-reduced-motion: reduce)")
    this.onMotionChange = () => this.updateMotion()
    this.onMediaActivation = event => { this.pause(); if (event.target !== this.element) this.clearMedia(this.slideTargets[this.index]) }
    document.addEventListener("wall-love-media-activate", this.onMediaActivation)
    this.onVisibilityChange = () => { if (document.hidden) this.pause() }
    this.motion.addEventListener("change", this.onMotionChange)
    document.addEventListener("visibilitychange", this.onVisibilityChange)
    this.controlsTarget.hidden = false
    this.element.dataset.enhanced = "true"
    this.updateMotion()
    this.show(0)
  }

  disconnect() {
    this.pause()
    document.removeEventListener("turbo:before-cache", this.onBeforeCache)
    this.motion?.removeEventListener("change", this.onMotionChange)
    document.removeEventListener("visibilitychange", this.onVisibilityChange)
    document.removeEventListener("wall-love-media-activate", this.onMediaActivation)
    this.slideTargets.forEach(slide => { this.clearMedia(slide); slide.hidden = false })
    if (this.hasControlsTarget) this.controlsTarget.hidden = true
    delete this.element.dataset.enhanced
  }

  updateMotion() {
    this.pause()
    this.toggleTarget.disabled = this.motion.matches
    this.toggleTarget.title = this.motion.matches ? "Automatic rotation is disabled by your reduced motion preference." : "Start automatic slide rotation"
  }

  previous() { this.pause(); this.show(this.index - 1) }
  next() { this.pause(); this.show(this.index + 1) }

  keydown(event) {
    if (event.target.closest("input, textarea, select")) return
    const positions = { ArrowLeft: this.index - 1, ArrowRight: this.index + 1, Home: 0, End: this.slideTargets.length - 1 }
    if (!(event.key in positions)) return
    event.preventDefault()
    this.pause()
    this.show(positions[event.key])
  }

  toggleRotation() {
    if (this.timer) { this.pause(); return }
    if (this.motion.matches) return
    this.timer = window.setInterval(() => this.show(this.index + 1), 7000)
    this.toggleTarget.textContent = "Pause slideshow"
    this.toggleTarget.setAttribute("aria-pressed", "true")
    this.statusTarget.textContent = "Automatic rotation is on. Pause to explore a post or recording."
  }

  pause() {
    const wasPlaying = Boolean(this.timer)
    window.clearInterval(this.timer)
    this.timer = null
    if (wasPlaying && this.hasStatusTarget) this.statusTarget.textContent = "Slideshow paused. Browse at your own pace."
    if (this.hasToggleTarget) {
      this.toggleTarget.textContent = "Play slideshow"
      this.toggleTarget.setAttribute("aria-pressed", "false")
    }
  }

  show(index) {
    const count = this.slideTargets.length
    if (!count) return
    this.index = (index + count) % count
    this.slideTargets.forEach((slide, position) => {
      if (position !== this.index) this.clearMedia(slide)
      slide.hidden = position !== this.index
    })
    this.counterTarget.textContent = `${this.index + 1} / ${count}`
    this.statusTarget.textContent = `Featured source ${this.index + 1} of ${count}. ${this.slideTargets[this.index].dataset.author}.`
  }

  clearMedia(slide) {
    slide.querySelector("[data-native-embed]")?.replaceChildren()
    const button = slide.querySelector("[data-load-media]")
    if (button) { button.hidden = false; button.disabled = false }
    const preview = slide.querySelector("[data-recording-preview]")
    if (preview) preview.hidden = false
    slide.dataset.generation = String(Number(slide.dataset.generation || 0) + 1)
    delete slide.dataset.loaded
  }

  loadRecording() {
    this.pause()
    const slide = this.slideTargets[this.index]
    const id = slide.dataset.videoId
    if (slide.dataset.platform !== "YouTube" || !/^[A-Za-z0-9_-]{11}$/.test(id || "") || slide.dataset.loaded) return
    this.element.dispatchEvent(new Event("wall-love-media-activate", { bubbles: true }))
    const iframe = recordingIframe(id, slide.dataset.author)
    slide.querySelector("[data-native-embed]").replaceChildren(iframe)
    slide.querySelector("[data-recording-preview]").hidden = true
    slide.querySelector("[data-load-media]").hidden = true
    slide.dataset.loaded = "true"
  }

}
