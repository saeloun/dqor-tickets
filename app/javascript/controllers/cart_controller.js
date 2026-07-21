import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["quantity", "total", "addOnGate", "coupon", "discount"]
  static values = { previewUrl: String }

  connect() {
    this.previewRequest = 0
    this.updateOrder()
  }

  disconnect() {
    clearTimeout(this.previewTimeout)
  }

  increment(event) {
    const quantity = this.quantityFor(event.currentTarget)
    const max = quantity.max ? Number(quantity.max) : Infinity
    quantity.value = Math.min(Number(quantity.value || 0) + 1, max)
    this.updateOrder()
  }

  decrement(event) {
    const quantity = this.quantityFor(event.currentTarget)
    quantity.value = Math.max(Number(quantity.value || 0) - 1, 0)
    this.updateOrder()
  }

  sync(event) {
    this.updateOrder()
  }

  couponChanged() {
    this.showSubtotal()
    this.queuePreview(400)
  }

  quantityFor(control) {
    return this.quantityTargets.find(quantity => quantity.dataset.ticketTypeId === control.dataset.ticketTypeId)
  }

  count(quantity) {
    const parsed = Number.parseInt(quantity.value || "0", 10)
    return quantity.type === "checkbox" ? Number(quantity.checked) : Math.max(0, Number.isNaN(parsed) ? 0 : parsed)
  }

  updateOrder() {
    this.showSubtotal()

    const addOnSelected = this.quantityTargets.some(quantity => quantity.dataset.ticketKind === "add-on" && this.count(quantity) > 0)
    const conferenceSelected = this.quantityTargets.some(quantity => quantity.dataset.ticketKind === "conference" && this.count(quantity) > 0)
    this.addOnGateTarget.hidden = !addOnSelected || conferenceSelected
    this.queuePreview()
  }

  showSubtotal() {
    this.totalTarget.textContent = this.formatMoney(this.subtotal)
  }

  queuePreview(delay = 0) {
    clearTimeout(this.previewTimeout)
    const request = ++this.previewRequest
    this.discountTarget.hidden = true
    if (!this.couponTarget.value.trim()) return

    this.previewTimeout = setTimeout(() => this.previewCoupon(request), delay)
  }

  async previewCoupon(request) {
    try {
      const response = await fetch(this.previewUrlValue, {
        method: "POST",
        headers: {
          "Accept": "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
        },
        body: JSON.stringify({
          checkout_preview: {
            coupon_code: this.couponTarget.value,
            items: this.quantityTargets.map(quantity => ({
              ticket_type_id: quantity.dataset.ticketTypeId,
              quantity: this.count(quantity)
            })).filter(item => item.quantity > 0)
          }
        })
      })
      if (!response.ok) throw new Error(response.statusText)

      const preview = await response.json()
      if (request !== this.previewRequest) return

      this.totalTarget.textContent = this.formatMoney(preview.total_paise)
      this.discountTarget.textContent = preview.coupon.applied
        ? `Coupon ${preview.coupon.code} applied · −${this.formatMoney(preview.discount_paise)}`
        : preview.coupon.message
      this.discountTarget.classList.toggle("coupon-message--applied", preview.coupon.applied)
      this.discountTarget.classList.toggle("coupon-message--invalid", !preview.coupon.applied)
      this.discountTarget.hidden = false
    } catch {
      if (request !== this.previewRequest) return

      this.showSubtotal()
      this.discountTarget.hidden = true
    }
  }

  formatMoney(paise) {
    const fractionDigits = paise % 100 === 0 ? 0 : 2
    return new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      minimumFractionDigits: fractionDigits,
      maximumFractionDigits: fractionDigits
    }).format(paise / 100)
  }

  get subtotal() {
    return this.quantityTargets.reduce((sum, quantity) => sum + this.count(quantity) * Number(quantity.dataset.unitPrice), 0)
  }
}
