import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["quantity", "attendees", "template", "total", "addOnGate"]

  connect() {
    this.quantityTargets.forEach(quantity => this.syncQuantity(quantity))
    this.updateOrder()
  }

  increment(event) {
    const quantity = this.quantityFor(event.currentTarget)
    const max = quantity.max ? Number(quantity.max) : Infinity
    quantity.value = Math.min(Number(quantity.value || 0) + 1, max)
    this.syncQuantity(quantity)
    this.updateOrder()
  }

  decrement(event) {
    const quantity = this.quantityFor(event.currentTarget)
    quantity.value = Math.max(Number(quantity.value || 0) - 1, 0)
    this.syncQuantity(quantity)
    this.updateOrder()
  }

  sync(event) {
    this.syncQuantity(event.currentTarget)
    this.updateOrder()
  }

  quantityFor(control) {
    return this.quantityTargets.find(quantity => quantity.dataset.ticketTypeId === control.dataset.ticketTypeId)
  }

  count(quantity) {
    const parsed = Number.parseInt(quantity.value || "0", 10)
    return quantity.type === "checkbox" ? Number(quantity.checked) : Math.max(0, Number.isNaN(parsed) ? 0 : parsed)
  }

  syncQuantity(quantity) {
    const count = this.count(quantity)
    const ticketTypeId = quantity.dataset.ticketTypeId
    const attendees = this.attendeesTargets.find(target => target.dataset.ticketTypeId === ticketTypeId)
    const template = this.templateTargets.find(target => target.dataset.ticketTypeId === ticketTypeId)

    while (attendees.children.length < count) {
      const index = attendees.children.length
      attendees.insertAdjacentHTML("beforeend", template.innerHTML.replaceAll("NEW_INDEX", index).replaceAll("NEW_NUMBER", index + 1))
    }
    while (attendees.children.length > count) attendees.lastElementChild.remove()
  }

  updateOrder() {
    const total = this.quantityTargets.reduce((sum, quantity) => sum + this.count(quantity) * Number(quantity.dataset.unitPrice), 0)
    this.totalTarget.textContent = new Intl.NumberFormat("en-IN", {
      style: "currency",
      currency: "INR",
      maximumFractionDigits: 0
    }).format(total / 100)

    const addOnSelected = this.quantityTargets.some(quantity => quantity.dataset.ticketKind === "add-on" && this.count(quantity) > 0)
    const conferenceSelected = this.quantityTargets.some(quantity => quantity.dataset.ticketKind === "conference" && this.count(quantity) > 0)
    this.addOnGateTarget.hidden = !addOnSelected || conferenceSelected
  }
}
