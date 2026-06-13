import { Controller } from "@hotwired/stimulus"

// Shows the field-mapping group (and extra config, e.g. the deals pipeline) for
// the currently selected sync target, hiding the rest. Inactive groups are
// disabled so their inputs never submit — only the chosen target's mapping is
// sent. Groups are <div data-connector-target-target="group" data-group="...">.
export default class extends Controller {
  static targets = ["select", "group"]

  connect() {
    this.update()
  }

  update() {
    const target = this.selectTarget.value
    this.groupTargets.forEach((group) => {
      const active = group.dataset.group === target
      group.hidden = !active
      group.querySelectorAll("input, select").forEach((el) => {
        el.disabled = !active
      })
    })
  }
}
