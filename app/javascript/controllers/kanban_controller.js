import { Controller } from "@hotwired/stimulus"

// Drag a deal card between stage columns; persist the move to the server.
// Optimistic: the card moves immediately, reverting (reload) on failure.
export default class extends Controller {
  static targets = ["column", "card"]
  static values = { moveUrl: String }

  dragstart(event) {
    this.draggedId = event.target.dataset.dealId
    event.dataTransfer.effectAllowed = "move"
    event.target.classList.add("is-dragging")
  }

  dragend(event) {
    event.target.classList.remove("is-dragging")
  }

  dragover(event) {
    event.preventDefault()
    event.currentTarget.classList.add("is-drag-over")
  }

  dragleave(event) {
    event.currentTarget.classList.remove("is-drag-over")
  }

  drop(event) {
    event.preventDefault()
    const column = event.currentTarget
    column.classList.remove("is-drag-over")
    const stageId = column.dataset.stageId
    const card = this.element.querySelector(`.kanban-card[data-deal-id="${this.draggedId}"]`)
    if (!card || !stageId) return
    column.querySelector(".kanban-cards").appendChild(card)
    this.persist(this.draggedId, stageId)
  }

  persist(dealId, stageId) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    fetch(`${this.moveUrlValue}/${dealId}/move`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token,
        "Accept": "application/json"
      },
      body: JSON.stringify({ pipeline_stage_id: stageId })
    }).then((response) => {
      if (!response.ok) window.location.reload()
    }).catch(() => window.location.reload())
  }
}
