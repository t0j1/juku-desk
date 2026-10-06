import { Controller } from "@hotwired/stimulus"

// 実行内容のラジオに合わせて、選んだ方の設定欄だけを出す（出さない方は無効にして送らない）
export default class extends Controller {
  static targets = [ "radio", "section" ]

  connect() { this.update() }

  update() {
    const current = this.radioTargets.find((r) => r.checked)?.value
    this.sectionTargets.forEach((section) => {
      const on = section.dataset.type === current
      section.hidden = !on
      section.querySelectorAll("input, select").forEach((el) => { el.disabled = !on })
    })
  }
}
