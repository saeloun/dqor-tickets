import { Controller } from "@hotwired/stimulus"
import { initializeCamera, interruptCamera, restartCamera } from "scanning/camera"

export default class extends Controller {
  static targets = ["date", "result", "count", "selection", "batchButton", "dialog", "confirmation", "outcomes", "control", "cameraStatus"]

  connect() {
    this.connected = true
    this.busy = false
    this.lastSecret = null
    this.updateSelection()
    this.initializeScanner()
  }

  initializeScanner() { initializeCamera(this, "checkin-reader", "Attendee search remains available.") }

  visibilityChanged() {
    if (document.hidden) this.interruptCamera()
  }

  interruptCamera() { interruptCamera(this, "Attendee search remains available.") }
  restartCamera() { return restartCamera(this, "Tap Request Camera Permissions and choose the back/rear camera. If access is denied, allow camera access in browser settings or use attendee search below.", true) }

  disconnect() {
    this.connected = false
    window.clearTimeout(this.resumeTimeout)
    this.requestController?.abort()
    this.scanner?.clear().catch(() => {})
    this.scanner = null
  }

  beforeCache() {
    this.requestController?.abort()
    this.dialogTarget.close()
    this.clearSelection()
    this.resultTarget.hidden = true
    this.outcomesTarget.replaceChildren()
  }

  changeDate(event) {
    if (this.busy) return
    this.busy = true
    this.element.setAttribute("aria-busy", "true")
    this.pauseScanner()
    this.show("warning", "Loading the selected date. Wait before checking in.")
    this.element.querySelectorAll("button").forEach(button => { button.disabled = true })
    this.selectionTargets.forEach(input => { input.disabled = true })
    event.currentTarget.form.requestSubmit()
  }

  scanTicket(event) {
    this.submitOne({ ticket_id: event.currentTarget.dataset.ticketId })
  }

  scan(secret) {
    if (this.busy || document.hidden || this.dialogTarget.open) return
    if (this.cameraInterrupted) {
      this.show("warning", "Camera paused. Tap Restart camera, then choose the back/rear camera. Attendee search remains available.")
      return
    }
    if (secret === this.lastSecret) return
    this.lastSecret = secret
    this.submitOne({ secret })
  }

  async submitOne(ticket) {
    if (this.busy) return
    if (!ticket.secret) this.lastSecret = null
    this.setBusy(true)
    this.pauseScanner()
    this.show("warning", "Waiting for server confirmation…")
    try {
      const body = await this.request("/checkin", { ...ticket, date: this.dateTarget.value })
      if (body.state !== "success" && body.state !== "warning") this.lastSecret = null
      this.show(body.state, body.message)
      this.updateCount(body)
      this.updateTicketStatus(body)
    } catch (error) {
      this.lastSecret = null
      this.show("error", error.message)
    } finally {
      this.setBusy(false)
      this.resumeTimeout = window.setTimeout(() => this.resumeScanner(), 1200)
    }
  }

  updateSelection() {
    const count = this.selectionTargets.filter(input => input.checked).length
    this.batchButtonTarget.textContent = `Review ${count} selected ticket${count === 1 ? "" : "s"}`
    this.batchButtonTarget.disabled = this.busy || count === 0
  }

  selectVisible() {
    this.selectionTargets.forEach(input => { input.checked = true })
    this.updateSelection()
  }

  clearSelection() {
    this.selectionTargets.forEach(input => { input.checked = false })
    this.updateSelection()
  }

  reviewBatch() {
    if (this.busy) return
    this.batchIds = this.selectionTargets.filter(input => input.checked).map(input => input.value)
    if (!this.batchIds.length) return
    this.batchDate = this.dateTarget.value
    this.confirmationTarget.replaceChildren()
    const summary = document.createElement("p")
    summary.textContent = `Check in ${this.batchIds.length} selected tickets for ${this.batchDate}? Only the attendees listed here will be processed.`
    this.confirmationTarget.append(summary)
    const list = document.createElement("ul")
    this.selectionTargets.filter(input => input.checked).forEach(input => {
      const item = document.createElement("li")
      item.textContent = input.dataset.attendee
      list.append(item)
    })
    this.confirmationTarget.append(list)
    this.pauseScanner()
    this.dialogTarget.showModal()
  }

  cancelBatch(event) {
    if (this.busy) { event?.preventDefault(); return }
    this.dialogTarget.close()
    this.resumeScanner()
  }

  async confirmBatch() {
    if (this.busy || !this.dialogTarget.open) return
    this.lastSecret = null
    this.setBusy(true)
    this.outcomesTarget.replaceChildren()
    this.show("warning", "Waiting for batch results. Do not admit attendees until confirmed.")
    try {
      const body = await this.request("/checkin/batch", { ticket_ids: this.batchIds, date: this.batchDate, confirmed: true })
      if (!Array.isArray(body.results)) throw new Error("Batch results unavailable. Retry safely to verify each ticket.")
      body.results.forEach(result => {
        const row = document.createElement("li")
        row.className = `checkin-result checkin-result--${result.state}`
        row.textContent = `${result.attendee || `Ticket #${result.ticket_id}`}: ${result.message}`
        this.outcomesTarget.append(row)
        this.updateTicketStatus(result)
      })
      const done = body.results.filter(result => result.state === "success").length
      this.show(done === body.results.length ? "success" : "warning", `${done} checked in; ${body.results.length - done} need attention. See every result below.`)
      this.updateCount(body)
      this.clearSelection()
    } catch (error) {
      this.show("error", error.message)
    } finally {
      this.dialogTarget.close()
      this.setBusy(false)
      this.resumeScanner()
      this.resultTarget.focus()
    }
  }

  async request(url, payload) {
    this.requestController = new AbortController()
    const timeout = window.setTimeout(() => this.requestController?.abort(), 15000)
    try {
      const response = await fetch(url, {
        method: "POST", signal: this.requestController.signal,
        headers: { "Accept": "application/json", "Content-Type": "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content ?? "" },
        body: JSON.stringify(payload)
      })
      if (response.redirected || response.status === 401) throw new Error("Session expired. Sign in before checking in.")
      const body = await response.json()
      if (!response.ok && ![409, 422, 404].includes(response.status)) throw new Error("Server could not confirm check-in. Retry safely to verify; a ticket may already have been recorded.")
      if (!response.ok && body.state !== "warning" && body.state !== "error") throw new Error("Check-in was not confirmed. Retry safely.")
      return body
    } catch (error) {
      if (error instanceof TypeError || error.name === "AbortError" || error instanceof SyntaxError) {
        throw new Error("Connection lost or response unavailable. Check-in is not confirmed; retry safely to verify each ticket. A request may already have been recorded.")
      }
      throw error
    } finally { window.clearTimeout(timeout) }
  }

  setBusy(value) {
    this.busy = value
    this.element.setAttribute("aria-busy", String(value))
    this.controlTargets.forEach(control => { control.disabled = value })
    this.selectionTargets.forEach(control => { control.disabled = value })
    this.updateSelection()
  }

  updateCount(body) {
    if (Number.isInteger(body.checked_in_count)) this.countTarget.textContent = String(body.checked_in_count)
    body.stats?.by_type?.forEach(row => {
      const count = Array.from(this.element.querySelectorAll("[data-type-count]")).find(node => node.dataset.typeCount === row.name)
      if (count) count.textContent = String(row.checked_in)
    })
  }

  updateTicketStatus(result) {
    const status = Array.from(this.element.querySelectorAll("[data-ticket-status]")).find(node => node.dataset.ticketStatus === String(result.ticket_id))
    if (status) status.textContent = result.message
  }

  pauseScanner() { try { this.scanner?.pause(true) } catch (_) {} }
  resumeScanner() { if (this.connected && !document.hidden && !this.cameraInterrupted && !this.busy && !this.dialogTarget.open) { try { this.scanner?.resume() } catch (_) {} } }

  show(state, message) {
    if (!this.connected) return
    const safeState = ["success", "warning", "error"].includes(state) ? state : "error"
    const className = `checkin-result checkin-result--${safeState}`
    const text = message || "Check-in was not confirmed. Retry safely."
    if (!this.resultTarget.hidden && this.resultTarget.className === className && this.resultTarget.textContent === text) return
    this.resultTarget.className = className
    this.resultTarget.textContent = text
    this.resultTarget.hidden = false
    this.resultTarget.focus({ preventScroll: true })
    this.resultTarget.scrollIntoView({ block: "nearest" })
  }
}
