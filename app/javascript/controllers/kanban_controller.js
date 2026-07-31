import { Controller } from "@hotwired/stimulus"

// Drag a card between columns and persist the move. Optimistic: the card moves
// immediately and the page reloads if the server refuses.
//
// Generic over what is being dragged — the deal pipeline and the work board
// both use it. The card carries data-item-id, the column carries
// data-target-id, and the caller supplies the URL template and the parameter
// name the server expects:
//
//   data-kanban-url-template-value="/deals/:id/move"
//   data-kanban-param-value="pipeline_stage_id"
export default class extends Controller {
  static targets = ["column", "card"]
  static values = { urlTemplate: String, param: String }

  dragstart(event) {
    this.draggedId = event.target.dataset.itemId
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
    const targetId = column.dataset.targetId
    const card = this.element.querySelector(`.kanban-card[data-item-id="${this.draggedId}"]`)
    if (!card || !targetId) return

    const sourceColumn = card.closest(".kanban-column")
    column.querySelector(".kanban-cards").appendChild(card)
    this.recount(sourceColumn, column)
    this.persist(this.draggedId, targetId)
  }

  // Counts and WIP flags are rendered server-side; keep them honest after an
  // optimistic move instead of waiting for a reload. data-total-count carries
  // the true server count when a column is capped; counting rendered cards
  // would turn 65 into 49 after one drag and hide a real WIP breach.
  recount(sourceColumn, targetColumn) {
    if (sourceColumn && targetColumn && sourceColumn !== targetColumn) {
      sourceColumn.dataset.totalCount = Math.max(0, this.totalCount(sourceColumn) - 1)
      targetColumn.dataset.totalCount = this.totalCount(targetColumn) + 1
    }

    new Set([sourceColumn, targetColumn].filter(Boolean)).forEach((column) => {
      const count = this.totalCount(column)
      const badge = column.querySelector(".kanban-count")
      if (badge) badge.textContent = count

      const limit = parseInt(column.dataset.wipLimit || "", 10)
      if (!isNaN(limit)) {
        const over = count > limit
        column.classList.toggle("is-over-wip", over)
        column.querySelector(".kanban-wip")?.classList.toggle("is-over", over)
        const warning = column.querySelector(".board-wip-warning")
        if (warning) warning.hidden = !over
      }
    })
  }

  totalCount(column) {
    const stored = parseInt(column.dataset.totalCount || "", 10)
    return isNaN(stored) ? column.querySelectorAll(".kanban-card").length : stored
  }

  persist(itemId, targetId) {
    const token = document.querySelector("meta[name='csrf-token']")?.content
    const url = this.urlTemplateValue.replace(":id", itemId)
    const body = {}
    body[this.paramValue] = targetId

    fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": token,
        "Accept": "application/json"
      },
      body: JSON.stringify(body)
    }).then((response) => {
      if (!response.ok || response.status === 202) window.location.reload()
    }).catch(() => window.location.reload())
  }
}
