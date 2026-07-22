import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "button"]

  async copy() {
    this.sourceTarget.select()

    try {
      await navigator.clipboard.writeText(this.sourceTarget.value)
    } catch (_) {
      document.execCommand("copy")
    }

    const original = this.buttonTarget.textContent
    this.buttonTarget.textContent = "Copied"
    window.clearTimeout(this.resetTimeout)
    this.resetTimeout = window.setTimeout(() => { this.buttonTarget.textContent = original }, 2000)
  }
}
