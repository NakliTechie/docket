import { Controller } from "@hotwired/stimulus"

// Case-view single-key actions. Any element with data-shortcut="x"
// inside this controller's scope is clicked/focused when its key is
// pressed. Documented in the help modal (?).
export default class extends Controller {
  connect() {
    this.onKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  onKeydown(event) {
    if (event.target.closest("input, textarea, select, [contenteditable]")) return
    if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return

    const el = this.element.querySelector(`[data-shortcut="${event.key}"]`)
    if (!el) return
    event.preventDefault()

    if (el.matches("textarea, input[type=text], input[type=search], input[type=email]")) {
      el.focus()
    } else {
      el.click()
    }
  }
}
