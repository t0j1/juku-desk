import { Controller } from "@hotwired/stimulus"

// ボタンで、パネルの表示・非表示を切り替える（aria-expanded を合わせる）
export default class extends Controller {
  static targets = [ "button", "panel" ]

  toggle() {
    const open = this.panelTarget.hidden
    this.panelTarget.hidden = !open
    this.buttonTarget.setAttribute("aria-expanded", String(open))
  }
}
