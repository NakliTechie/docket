import { Controller } from "@hotwired/stimulus"

// j/k row navigation + Enter/o to open, for list views. Rows declare
// data-keynav-href.
export default class extends Controller {
  static targets = ["list"]

  connect() {
    this.index = -1
    this.onKeydown = this.onKeydown.bind(this)
    document.addEventListener("keydown", this.onKeydown)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
  }

  rows() {
    return Array.from(this.listTarget.querySelectorAll("[data-keynav-href]"))
  }

  onKeydown(event) {
    // Don't hijack keys (especially Enter/o) while a form field or an
    // interactive element is focused — the link/button should win.
    if (event.target.closest("input, textarea, select, [contenteditable], a, button, [role=button], summary")) return
    if (event.altKey || event.ctrlKey || event.metaKey) return

    switch (event.key) {
      case "j":
        event.preventDefault()
        this.move(1)
        break
      case "k":
        event.preventDefault()
        this.move(-1)
        break
      case "Enter":
      case "o":
        if (this.index >= 0) {
          event.preventDefault()
          const row = this.rows()[this.index]
          if (row) window.Turbo.visit(row.dataset.keynavHref)
        }
        break
    }
  }

  move(delta) {
    const rows = this.rows()
    if (rows.length === 0) return
    this.index = Math.min(Math.max(this.index + delta, 0), rows.length - 1)
    rows.forEach((row, i) => row.classList.toggle("row-selected", i === this.index))
    rows[this.index].scrollIntoView({ block: "nearest" })
  }
}
