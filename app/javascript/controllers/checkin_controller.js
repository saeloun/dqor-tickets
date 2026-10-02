import { Controller } from "@hotwired/stimulus"
import "html5-qrcode"

export default class extends Controller {
  static targets = ["date", "result", "count", "selection", "batchButton", "dialog", "confirmation", "outcomes", "control"]

  connect() {
    this.connected = true
    this.busy = false
    this.updateSelection()
    const Scanner = window.__Html5QrcodeLibrary__?.Html5QrcodeScanner
    if (!Scanner) return this.show("error", "Camera scanner unavailable. Use attendee search below.")
    this.scanner = new Scanner("checkin-reader", { fps: 10, qrbox: { width: 250, height: 250 } }, false)
    this.scanner.render(secret => this.scan(secret), () => {})
  }

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
    if (!this.busy) event.currentTarget.form.requestSubmit()
  }

  scanTicket(event) {
    this.submitOne({ ticket_id: event.currentTarget.dataset.ticketId })
  }

  scan(secret) {
    if (this.busy || this.dialogTarget.open) return
    if (secret === this.lastSecret && Date.now() - this.lastScan < 3000) return
    this.lastSecret = secret
    this.lastScan = Date.now()
    this.submitOne({ secret })
  }

  async submitOne(ticket) {
    if (this.busy) return
    this.setBusy(true)
    this.pauseScanner()
    this.show("warning", "Waiting for server confirmation…")
    try {
      const body = await this.request("/checkin", { ...ticket, date: this.dateTarget.value })
      this.show(body.state, body.message)
      this.updateCount(body)
      this.updateTicketStatus(body)
    } catch (error) {
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
  resumeScanner() { if (this.connected && !this.busy && !this.dialogTarget.open) { try { this.scanner?.resume() } catch (_) {} } }

  show(state, message) {
    if (!this.connected) return
    const safeState = ["success", "warning", "error"].includes(state) ? state : "error"
    this.resultTarget.className = `checkin-result checkin-result--${safeState}`
    this.resultTarget.textContent = message || "Check-in was not confirmed. Retry safely."
    this.resultTarget.hidden = false
  }
}
