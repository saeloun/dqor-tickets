import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.updateButton()
  }

  toggle() {
    const theme = window.__dqorTheme.getCurrentTheme() === "dark" ? "light" : "dark"
    window.__dqorTheme.applyTheme(theme)
    window.__dqorTheme.storeTheme(theme)
    this.updateButton()
  }

  updateButton() {
    const dark = window.__dqorTheme.getCurrentTheme() === "dark"
    this.buttonTarget.setAttribute("aria-label", `Switch to ${dark ? "light" : "dark"} theme`)
    this.buttonTarget.setAttribute("aria-pressed", dark)
  }
}
