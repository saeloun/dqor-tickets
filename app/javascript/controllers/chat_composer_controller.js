import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input"]

  submitOnEnter(event) {
    if (event.shiftKey) return
    event.preventDefault()
    if (this.inputTarget.value.trim().length > 0) {
      this.element.requestSubmit()
    }
  }

  afterSubmit(event) {
    if (event.detail.success) {
      this.inputTarget.value = ""
      this.autoGrow()
      this.inputTarget.focus()
    }
  }

  autoGrow() {
    this.inputTarget.style.height = "auto"
    this.inputTarget.style.height = `${Math.min(this.inputTarget.scrollHeight, 140)}px`
  }
}
