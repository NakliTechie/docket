import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, template: String }
  static targets = ["warning"]

  connect() {
    this.heartbeat()
    this.timer = window.setInterval(() => this.heartbeat(), 30000)
  }

  disconnect() { window.clearInterval(this.timer) }

  async heartbeat() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    const response = await fetch(this.urlValue, {
      method: "POST",
      headers: { "Accept": "application/json", "X-CSRF-Token": token }
    })
    if (!response.ok) return
    const { agents } = await response.json()
    this.warningTarget.textContent = agents.length ? this.templateValue.replace("%{agents}", agents.join(", ")) : ""
    this.warningTarget.hidden = agents.length === 0
  }
}
