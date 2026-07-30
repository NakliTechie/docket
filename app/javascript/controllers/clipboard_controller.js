import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "feedback"]

  async copy(event) {
    const value = this.sourceTarget.value || this.sourceTarget.textContent.trim()
    const label = event.currentTarget.dataset.clipboardLabelValue
    this.feedbackTarget.textContent = label

    try {
      await navigator.clipboard.writeText(value)
    } catch (_error) {
      const textarea = document.createElement("textarea")
      textarea.value = value
      textarea.setAttribute("readonly", "")
      textarea.className = "clipboard-proxy"
      document.body.appendChild(textarea)
      textarea.select()
      document.execCommand("copy")
      textarea.remove()
    }
  }
}
