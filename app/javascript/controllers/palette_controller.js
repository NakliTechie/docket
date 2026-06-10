import { Controller } from "@hotwired/stimulus"

// Command palette: type-to-filter command list, arrows + Enter to run.
export default class extends Controller {
  static targets = ["input", "list"]

  filter() {
    const q = this.inputTarget.value.toLowerCase()
    this.items().forEach((item) => {
      item.hidden = q !== "" && !item.dataset.paletteLabel.toLowerCase().includes(q)
    })
    this.highlight(0)
  }

  onKeydown(event) {
    const visible = this.visibleItems()
    const current = visible.findIndex((i) => i.classList.contains("palette-active"))
    if (event.key === "ArrowDown") {
      event.preventDefault()
      this.highlight(Math.min(current + 1, visible.length - 1))
    } else if (event.key === "ArrowUp") {
      event.preventDefault()
      this.highlight(Math.max(current - 1, 0))
    } else if (event.key === "Enter") {
      event.preventDefault()
      const target = visible[current >= 0 ? current : 0]
      if (target) window.Turbo.visit(target.dataset.paletteHref)
      this.close()
    } else if (event.key === "Escape") {
      this.close()
    }
  }

  items() {
    return Array.from(this.listTarget.querySelectorAll("[data-palette-href]"))
  }

  visibleItems() {
    return this.items().filter((i) => !i.hidden)
  }

  highlight(index) {
    this.visibleItems().forEach((item, i) => item.classList.toggle("palette-active", i === index))
  }

  go(event) {
    window.Turbo.visit(event.currentTarget.dataset.paletteHref)
    this.close()
  }

  close() {
    this.element.close()
  }
}
