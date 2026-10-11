import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["card", "filters", "filter", "more", "status"]
  static values = { limit: { type: Number, default: 18 } }

  connect() {
    this.visibleLimit = this.limitValue
    this.filtersTarget.hidden = false
    this.render()
  }

  disconnect() {
    this.cardTargets.forEach(card => { card.hidden = false })
    this.filtersTarget.hidden = true
    this.moreTarget.hidden = true
  }

  filter() {
    this.visibleLimit = this.limitValue
    this.element.dispatchEvent(new Event("wall-love-media-activate", { bubbles: true }))
    this.render()
  }

  more() { this.visibleLimit += this.limitValue; this.render() }

  render() {
    const group = this.filterTarget.value
    const cards = this.cardTargets.filter(card => group === "all" || card.dataset.groups.split(" ").includes(group))
    this.cardTargets.forEach(card => { card.hidden = !cards.includes(card) || cards.indexOf(card) >= this.visibleLimit })
    const shown = Math.min(this.visibleLimit, cards.length)
    this.moreTarget.hidden = shown === cards.length
    this.moreTarget.textContent = `Load ${Math.min(this.limitValue, cards.length - shown)} more moments`
    this.statusTarget.textContent = `Showing ${shown} of ${cards.length} sources.`
  }
}
