import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["toggle"]

  toggle() {
    const open = this.element.classList.toggle("menu-open")
    this.toggleTarget.setAttribute("aria-expanded", String(open))
  }

  closeFromLink(event) {
    if (event.target.closest("a")) this.close()
  }

  groupToggled(event) {
    if (!event.target.open) return

    this.element.querySelectorAll("details.nav-group[open]").forEach((group) => {
      if (group !== event.target) group.removeAttribute("open")
    })
  }

  keydown(event) {
    if (event.key !== "Escape") return

    this.close()
    this.toggleTarget.focus()
  }

  close() {
    this.element.classList.remove("menu-open")
    this.toggleTarget.setAttribute("aria-expanded", "false")
    this.element.querySelectorAll("details.nav-group[open]").forEach((group) => {
      group.removeAttribute("open")
    })
  }
}
