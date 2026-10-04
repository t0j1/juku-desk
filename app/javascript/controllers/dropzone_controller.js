import { Controller } from "@hotwired/stimulus"

// Visual drop zone around a native file input; keeps the input as the real (keyboard-focusable) control.
export default class extends Controller {
  static targets = ["input", "label", "submit"]

  connect() { this.update() }

  update() {
    const file = this.inputTarget.files[0]
    this.labelTarget.textContent = file ? file.name : this.labelTarget.dataset.empty
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = !file
      this.submitTarget.setAttribute("aria-disabled", String(!file))
    }
  }

  dragover(e) { e.preventDefault(); this.element.dataset.dragging = "true" }
  dragleave() { delete this.element.dataset.dragging }
  drop(e) {
    e.preventDefault(); delete this.element.dataset.dragging
    if (e.dataTransfer.files.length) { this.inputTarget.files = e.dataTransfer.files; this.update() }
  }
}
