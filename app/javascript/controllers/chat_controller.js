import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["messages"]
  static values = { currentUserId: Number }

  connect() {
    this.tagAll()
    this.scrollToBottom()
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === 1) this.tag(node)
        })
      }
      this.scrollToBottom()
    })
    if (this.hasMessagesTarget) {
      this.observer.observe(this.messagesTarget, { childList: true })
    }
  }

  disconnect() {
    if (this.observer) this.observer.disconnect()
  }

  tagAll() {
    if (!this.hasMessagesTarget) return
    this.messagesTarget.querySelectorAll(".chat-message").forEach((node) => this.tag(node))
  }

  tag(node) {
    if (!node.classList || !node.classList.contains("chat-message")) return
    if (Number(node.dataset.senderId) === this.currentUserIdValue) {
      node.classList.add("chat-message--mine")
    }
  }

  scrollToBottom() {
    if (this.hasMessagesTarget) {
      this.messagesTarget.scrollTop = this.messagesTarget.scrollHeight
    }
  }
}
