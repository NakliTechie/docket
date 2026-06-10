import { Controller } from "@hotwired/stimulus"

// Minimal <dialog> opener/closer for the help modal and palette.
export default class extends Controller {
  open() {
    this.element.showModal()
  }

  close() {
    this.element.close()
  }

  backdropClose(event) {
    if (event.target === this.element) this.element.close()
  }
}
