import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["quantity", "attendees", "template"]

  connect() {
    this.quantityTargets.forEach(quantity => this.sync({ currentTarget: quantity }))
  }

  sync(event) {
    const quantity = event.currentTarget
    const parsed = Number.parseInt(quantity.value || "0", 10)
    const count = quantity.type === "checkbox" ? Number(quantity.checked) : Math.max(0, Number.isNaN(parsed) ? 0 : parsed)
    const ticketTypeId = quantity.dataset.ticketTypeId
    const attendees = this.attendeesTargets.find(target => target.dataset.ticketTypeId === ticketTypeId)
    const template = this.templateTargets.find(target => target.dataset.ticketTypeId === ticketTypeId)

    while (attendees.children.length < count) {
      const index = attendees.children.length
      attendees.insertAdjacentHTML("beforeend", template.innerHTML.replaceAll("NEW_INDEX", index).replaceAll("NEW_NUMBER", index + 1))
    }
    while (attendees.children.length > count) attendees.lastElementChild.remove()
  }
}
