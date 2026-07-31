import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["body"]

  bold() { this.wrap("**", "**", "bold text") }
  italic() { this.wrap("_", "_", "italic text") }
  code() { this.wrap("`", "`", "code") }
  link() { this.wrap("[", "](https://)", "link text") }

  wrap(prefix, suffix, fallback) {
    const textarea = this.bodyTarget
    const start = textarea.selectionStart ?? textarea.value.length
    const end = textarea.selectionEnd ?? start
    const selected = textarea.value.slice(start, end) || fallback
    textarea.setRangeText(`${prefix}${selected}${suffix}`, start, end, "select")
    textarea.focus()
    textarea.dispatchEvent(new Event("input", { bubbles: true }))
  }
}
