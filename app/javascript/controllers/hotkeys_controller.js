import { Controller } from "@hotwired/stimulus"

// Global key bindings (staff console): ? help · Ctrl/Cmd+K palette ·
// / focus search. Never fires while typing in a form control, and
// never overrides browser or screen-reader bindings.
export default class extends Controller {
  connect() {
    this.onKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  onKeydown(event) {
    if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k") {
      event.preventDefault()
      this.openPalette()
      return
    }
    if (this.typingContext(event)) return
    if (event.altKey || event.ctrlKey || event.metaKey) return

    if (event.key === "?") {
      event.preventDefault()
      this.openDialog("help-modal")
    } else if (event.key === "/") {
      const search = document.querySelector("input[type=search]")
      if (search) {
        event.preventDefault()
        search.focus()
      }
    }
  }

  openPalette() {
    this.openDialog("command-palette")
    const input = document.querySelector("#command-palette input")
    if (input) { input.value = ""; input.dispatchEvent(new Event("input")); input.focus() }
  }

  openHelp() {
    this.openDialog("help-modal")
  }

  openDialog(id) {
    const dialog = document.getElementById(id)
    if (dialog && !dialog.open) dialog.showModal()
  }

  typingContext(event) {
    return event.target.closest("input, textarea, select, [contenteditable]")
  }
}
