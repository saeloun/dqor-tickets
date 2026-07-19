import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "countdown", "timer"]
  static values = {
    key: String,
    orderId: String,
    name: String,
    email: String,
    phone: String,
    amount: Number,
    expiresAt: String,
    callbackUrl: String,
    csrf: String
  }

  connect() {
    this.tick()
    this.timer = window.setInterval(() => this.tick(), 1000)
  }

  disconnect() {
    window.clearInterval(this.timer)
  }

  open() {
    if (!this.orderIdValue) {
      window.location.reload()
      return
    }
    new window.Razorpay({
      key: this.keyValue,
      order_id: this.orderIdValue,
      amount: this.amountValue,
      currency: "INR",
      name: "Deccan Queen on Rails",
      prefill: { name: this.nameValue, email: this.emailValue, contact: this.phoneValue },
      theme: { color: "#9b1c31" },
      handler: response => this.submit(response)
    }).open()
  }

  tick() {
    const remaining = Math.max(0, Math.floor((Date.parse(this.expiresAtValue) - Date.now()) / 1000))
    const minutes = String(Math.floor(remaining / 60)).padStart(2, "0")
    const seconds = String(remaining % 60).padStart(2, "0")
    this.countdownTarget.textContent = `${minutes}:${seconds}`
    this.timerTarget.classList.toggle("countdown-pill--urgent", remaining < 300)
    this.buttonTarget.disabled = remaining === 0
  }

  submit(response) {
    const form = document.createElement("form")
    form.method = "post"
    form.action = this.callbackUrlValue
    this.addField(form, "authenticity_token", this.csrfValue)
    Object.entries(response).forEach(([name, value]) => this.addField(form, name, value))
    document.body.appendChild(form)
    form.submit()
  }

  addField(form, name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    form.appendChild(input)
  }
}
