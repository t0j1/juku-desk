import { Controller } from "@hotwired/stimulus"

// 一覧のチェックボックス：全選択と、選んだ件数に応じた「選択した問題を承認」の有効化
export default class extends Controller {
  static targets = [ "item", "all", "button", "count" ]

  connect() { this.update() }

  toggleAll() {
    this.itemTargets.forEach((input) => { input.checked = this.allTarget.checked })
    this.update()
  }

  update() {
    const checked = this.itemTargets.filter((input) => input.checked).length
    if (this.hasButtonTarget) this.buttonTarget.disabled = checked === 0
    if (this.hasCountTarget) this.countTarget.textContent = checked
    if (this.hasAllTarget) this.allTarget.checked = checked > 0 && checked === this.itemTargets.length
  }
}
