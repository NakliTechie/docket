import { Controller } from "@hotwired/stimulus"

// Inserts the selected macro's (server-interpolated) text into the
// composer at the cursor and records the macro id for audit metadata.
export default class extends Controller {
  static targets = ["select", "body", "macroId"]

  insert() {
    const option = this.selectTarget.selectedOptions[0]
    if (!option || !option.dataset.body) return

    const textarea = this.bodyTarget
    const start = textarea.selectionStart ?? textarea.value.length
    const before = textarea.value.slice(0, start)
    const after = textarea.value.slice(textarea.selectionEnd ?? start)
    textarea.value = before + option.dataset.body + after
    textarea.focus()
    if (this.hasMacroIdTarget) this.macroIdTarget.value = option.value
    this.selectTarget.selectedIndex = 0
  }
}
