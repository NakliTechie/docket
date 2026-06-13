import { Controller } from "@hotwired/stimulus"

// Inserts a knowledge-base article link/snippet (PG3) into the reply composer
// at the cursor. The composer lives in a sibling panel, so we find it by name
// rather than a Stimulus target.
export default class extends Controller {
  insert(event) {
    const snippet = event.currentTarget.dataset.snippet
    if (!snippet) return

    const textarea = document.querySelector('textarea[name="message[body]"]')
    if (!textarea) return

    const start = textarea.selectionStart ?? textarea.value.length
    const end = textarea.selectionEnd ?? start
    const before = textarea.value.slice(0, start)
    const after = textarea.value.slice(end)
    const lead = before && !before.endsWith("\n") ? "\n\n" : ""
    textarea.value = before + lead + snippet + after
    textarea.focus()
  }
}
