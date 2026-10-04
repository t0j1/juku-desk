import { Controller } from "@hotwired/stimulus"

// まとめて再構造化の進み具合：処理中（active）のあいだだけ、数秒ごとに枠（turbo-frame）を読み直す
export default class extends Controller {
  static values = { active: Boolean, url: String, interval: { type: Number, default: 5000 } }

  connect() {
    if (!this.activeValue) return
    this.timer = setTimeout(() => {
      const frame = this.element.closest("turbo-frame")
      if (frame) frame.src = `${this.urlValue}?t=${Date.now()}`
    }, this.intervalValue)
  }

  disconnect() { clearTimeout(this.timer) }
}
