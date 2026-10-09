import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, active: Boolean }

  connect() {
    this.disconnect()
    if (this.activeValue) this.timer = window.setInterval(() => this.reload(), 8000)
  }

  disconnect() {
    window.clearInterval(this.timer)
    this.timer = null
  }

  reload() {
    const frame = this.element.closest("turbo-frame")
    if (frame && !frame.hasAttribute("busy")) frame.src = `${this.urlValue}?poll=${Date.now()}`
  }
}
