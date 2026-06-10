import { Controller } from "@hotwired/stimulus"

// Inserts an AI-suggested reply into the composer (insert-and-edit,
// never auto-send) and marks the hidden ai_suggested flag so usage is
// noted in the audit trail.
export default class extends Controller {
  static targets = ["text"]

  insert() {
    const composer = document.querySelector("textarea[data-macro-target=body]") ||
                     document.querySelector(".composer textarea")
    if (!composer) return
    composer.value = this.textTarget.textContent.trim()
    composer.focus()
    const flag = document.getElementById("composer-ai-suggested")
    if (flag) flag.value = "true"
  }
}
