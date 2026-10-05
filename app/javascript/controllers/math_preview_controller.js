import { Controller } from "@hotwired/stimulus"
import { renderMath } from "lib/math"

// 編集画面で、入力しているその場で数式の見た目を確認する。入力欄ごとに preview を対にする。
export default class extends Controller {
  static targets = [ "input", "preview" ]

  connect() {
    this.inputTargets.forEach((_, i) => this.update(i))
  }

  refresh(event) {
    this.update(this.inputTargets.indexOf(event.target))
  }

  update(i) {
    const input = this.inputTargets[i]
    const preview = this.previewTargets[i]
    if (!input || !preview) return
    preview.textContent = input.value
    preview.hidden = !/\$/.test(input.value)
    if (!preview.hidden) renderMath(preview)
  }
}
