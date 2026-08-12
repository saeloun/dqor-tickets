import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "status"]
  static values = { compact: { type: Boolean, default: false } }

  connect() {
    this.publicKey = document.querySelector('meta[name="vapid-public-key"]')?.content
    if (!this.supported()) {
      this.render("unsupported")
      return
    }
    this.refresh()
  }

  supported() {
    return (
      this.publicKey &&
      "serviceWorker" in navigator &&
      "PushManager" in window &&
      "Notification" in window
    )
  }

  async refresh() {
    if (Notification.permission === "denied") {
      this.render("denied")
      return
    }
    const subscription = await this.currentSubscription()
    this.render(subscription ? "on" : "off")
  }

  async currentSubscription() {
    const registration = await navigator.serviceWorker.ready
    return registration.pushManager.getSubscription()
  }

  async toggle() {
    const subscription = await this.currentSubscription()
    if (subscription) {
      await this.unsubscribe(subscription)
    } else {
      await this.subscribe()
    }
  }

  async subscribe() {
    this.setBusy(true)
    try {
      const permission = await Notification.requestPermission()
      if (permission !== "granted") {
        this.render(permission === "denied" ? "denied" : "off")
        return
      }
      const registration = await navigator.serviceWorker.ready
      const subscription = await registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: this.urlBase64ToUint8Array(this.publicKey)
      })
      const response = await fetch("/account/push_subscriptions", {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken() },
        body: JSON.stringify({ subscription: subscription.toJSON() })
      })
      this.render(response.ok ? "on" : "off")
    } catch (error) {
      this.render("off")
    } finally {
      this.setBusy(false)
    }
  }

  async unsubscribe(subscription) {
    this.setBusy(true)
    try {
      await fetch("/account/push_subscriptions", {
        method: "DELETE",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrfToken() },
        body: JSON.stringify({ endpoint: subscription.endpoint })
      })
      await subscription.unsubscribe()
      this.render("off")
    } catch (error) {
      this.render("on")
    } finally {
      this.setBusy(false)
    }
  }

  render(state) {
    const states = {
      on: ["You’ll get alerts on this device.", "Turn off notifications"],
      off: ["Get a heads-up for schedule changes and conference updates.", "Enable notifications"],
      denied: ["Notifications are blocked in your browser settings for this site.", null],
      unsupported: ["This device doesn’t support push notifications.", null]
    }
    const [status, label] = states[state] || states.off
    if (this.compactValue) {
      this.element.hidden = state !== "off"
      if (state !== "off") return
    }
    if (this.hasStatusTarget) this.statusTarget.textContent = status
    if (this.hasButtonTarget) {
      if (label) {
        this.buttonTarget.textContent = label
        this.buttonTarget.hidden = false
      } else {
        this.buttonTarget.hidden = true
      }
    }
  }

  setBusy(busy) {
    if (this.hasButtonTarget) this.buttonTarget.disabled = busy
  }

  csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }

  urlBase64ToUint8Array(base64String) {
    const padding = "=".repeat((4 - (base64String.length % 4)) % 4)
    const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(base64)
    const output = new Uint8Array(raw.length)
    for (let i = 0; i < raw.length; i++) output[i] = raw.charCodeAt(i)
    return output
  }
}
