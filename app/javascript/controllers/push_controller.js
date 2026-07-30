import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "status"]
  static values = { key: String }

  connect() {
    if (!this.supported) return
    this.element.hidden = false
    this.refresh()
  }

  async refresh() {
    const registration = await navigator.serviceWorker.ready
    const existing = await registration.pushManager.getSubscription()
    if (existing) this.markSubscribed()
  }

  async subscribe() {
    if (!this.supported) return

    const permission = await Notification.requestPermission()
    if (permission !== "granted") return this.setStatus("Notifications are blocked in your browser settings.")

    const registration = await navigator.serviceWorker.ready
    const subscription = await registration.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: this.applicationServerKey
    })

    const response = await fetch("/push_subscriptions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? ""
      },
      body: JSON.stringify({ subscription: subscription.toJSON() })
    })

    if (response.ok) this.markSubscribed()
    else this.setStatus("Could not enable notifications. Please try again.")
  }

  markSubscribed() {
    if (this.hasButtonTarget) this.buttonTarget.hidden = true
    this.setStatus("You’re subscribed to conference updates.")
  }

  setStatus(text) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = text
    this.statusTarget.hidden = false
  }

  get supported() {
    return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
  }

  get applicationServerKey() {
    const base64 = this.keyValue.replace(/-/g, "+").replace(/_/g, "/")
    const padded = base64.padEnd(base64.length + (4 - (base64.length % 4)) % 4, "=")
    const raw = atob(padded)
    return Uint8Array.from(raw, char => char.charCodeAt(0))
  }
}
