import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["thread", "form", "body", "status", "submit"]
  static values = { token: String, messageUrl: String, error: String, you: String, staff: String }

  connect() {
    this.consumer = createConsumer()
    this.subscription = this.consumer.subscriptions.create(
      { channel: "LiveChatChannel", token: this.tokenValue },
      {
        received: (message) => this.appendMessage(message),
        rejected: () => this.setStatus(this.errorValue)
      }
    )
    this.scrollToLatest()
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  async send(event) {
    event.preventDefault()
    this.submitTarget.disabled = true
    this.setStatus("")
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(this.messageUrlValue, {
      method: "POST",
      headers: { "Accept": "application/json", "X-CSRF-Token": token },
      body: new FormData(this.formTarget)
    })
    const payload = await response.json()
    if (response.ok) {
      this.appendMessage(payload)
      this.bodyTarget.value = ""
      this.bodyTarget.focus()
    } else {
      this.setStatus(payload.error || this.errorValue)
    }
    this.submitTarget.disabled = false
  }

  appendMessage(message) {
    if (this.threadTarget.querySelector(`[data-message-id="${message.id}"]`)) return

    const article = document.createElement("article")
    article.className = `thread-message direction-${message.direction}`
    article.dataset.messageId = message.id

    const head = document.createElement("div")
    head.className = "thread-message-head"
    const author = document.createElement("span")
    author.className = "thread-message-author"
    author.textContent = message.direction === "inbound" ? this.youValue : this.staffValue
    const time = document.createElement("span")
    time.textContent = new Intl.DateTimeFormat(document.documentElement.lang, {
      dateStyle: "short", timeStyle: "short"
    }).format(new Date(message.created_at))
    head.append(author, time)

    const body = document.createElement("div")
    body.className = "thread-message-body"
    body.textContent = message.body
    article.append(head, body)
    this.threadTarget.append(article)
    this.scrollToLatest()
  }

  setStatus(message) { this.statusTarget.textContent = message }
  scrollToLatest() { this.threadTarget.lastElementChild?.scrollIntoView({ block: "nearest" }) }
}
