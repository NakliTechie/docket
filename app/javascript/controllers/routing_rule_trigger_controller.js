import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["type", "schedule"]

  connect() {
    this.sync()
  }

  sync() {
    const scheduled = this.typeTarget.value === "elapsed_time"
    this.scheduleTarget.hidden = !scheduled
    this.scheduleTarget.querySelectorAll("input, select").forEach((field) => {
      field.disabled = !scheduled
    })
  }
}
