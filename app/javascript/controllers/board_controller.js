import { Controller } from "@hotwired/stimulus"

// Board-shell behaviour: filtering and column collapse.
//
// Filtering DIMS non-matching cards rather than hiding them. That is a
// deliberate choice carried over from KanZen: hiding makes a board lie about
// its own shape — column counts and the distribution of work stop matching
// what you see. Dimming keeps the whole board legible while pulling your eye
// to the matches.
export default class extends Controller {
  static targets = ["query", "card", "column"]

  filter() {
    const query = this.queryTarget.value.trim().toLowerCase()

    this.cardTargets.forEach((card) => {
      const matches = query === "" || card.textContent.toLowerCase().includes(query)
      card.classList.toggle("is-dimmed", !matches)
    })
  }

  clear() {
    this.queryTarget.value = ""
    this.filter()
  }

  // Collapse is per column and survives a reload — a board you re-collapse on
  // every visit is a board you stop collapsing.
  toggleColumn(event) {
    const column = event.currentTarget.closest(".kanban-column")
    if (!column) return

    const collapsed = column.classList.toggle("is-collapsed")
    const key = `docket.board.collapsed.${column.dataset.targetId}`
    collapsed ? localStorage.setItem(key, "1") : localStorage.removeItem(key)
  }

  connect() {
    this.columnTargets.forEach((column) => {
      if (localStorage.getItem(`docket.board.collapsed.${column.dataset.targetId}`)) {
        column.classList.add("is-collapsed")
      }
    })
  }
}
