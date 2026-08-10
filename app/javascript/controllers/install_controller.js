import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["text", "installButton"]

  connect() {
    if (this.dismissed || this.standalone) return

    this.onBeforeInstall = event => {
      event.preventDefault()
      this.deferredPrompt = event
      if (this.hasInstallButtonTarget) this.installButtonTarget.hidden = false
      this.reveal()
    }
    window.addEventListener("beforeinstallprompt", this.onBeforeInstall)

    this.onResize = () => { if (!this.element.hidden) this.reserveSpace() }
    window.addEventListener("resize", this.onResize)

    if (this.ios && this.hasTextTarget) {
      this.textTarget.textContent = "Tap Share, then Add to Home Screen to install."
      this.reveal()
    }
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.onBeforeInstall)
    window.removeEventListener("resize", this.onResize)
    this.clearSpace()
  }

  reveal() {
    this.element.hidden = false
    this.reserveSpace()
  }

  // The banner is position:fixed at the bottom, so reserve equal page space or
  // it covers content (e.g. the first ticket's price/quantity, the pay button).
  reserveSpace() {
    requestAnimationFrame(() => {
      const height = this.element.offsetHeight
      if (height) document.body.style.paddingBottom = `${height}px`
    })
  }

  clearSpace() {
    document.body.style.paddingBottom = ""
  }

  async install() {
    if (!this.deferredPrompt) return
    this.deferredPrompt.prompt()
    await this.deferredPrompt.userChoice
    this.deferredPrompt = null
    this.dismiss()
  }

  dismiss() {
    try { localStorage.setItem("dqor-install-dismissed", "1") } catch (_) {}
    this.element.hidden = true
    this.clearSpace()
  }

  get dismissed() {
    try { return localStorage.getItem("dqor-install-dismissed") === "1" } catch (_) { return false }
  }

  get standalone() {
    return window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true
  }

  get ios() {
    return /iphone|ipad|ipod/i.test(window.navigator.userAgent) && !window.MSStream
  }
}
