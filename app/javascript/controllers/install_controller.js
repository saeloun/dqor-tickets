import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["text", "installButton"]

  connect() {
    if (this.dismissed || this.standalone) return

    this.onBeforeInstall = event => {
      event.preventDefault()
      this.deferredPrompt = event
      if (this.hasInstallButtonTarget) this.installButtonTarget.hidden = false
      this.element.hidden = false
    }
    window.addEventListener("beforeinstallprompt", this.onBeforeInstall)

    if (this.ios && this.hasTextTarget) {
      this.textTarget.textContent = "Tap Share, then Add to Home Screen to install."
      this.element.hidden = false
    }
  }

  disconnect() {
    window.removeEventListener("beforeinstallprompt", this.onBeforeInstall)
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
