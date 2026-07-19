import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, active: Boolean }

  connect() {
    if (this.activeValue) this.timer = window.setInterval(() => this.reload(), 3000)
  }

  disconnect() {
    window.clearInterval(this.timer)
  }

  reload() {
    this.element.src = `${this.urlValue}?poll=${Date.now()}`
  }
}
