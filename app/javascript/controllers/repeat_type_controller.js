import { Controller } from "@hotwired/stimulus"

// 繰り返しに合わせて、曜日・日付の欄を出す
export default class extends Controller {
  static targets = [ "select", "weekdays", "date" ]

  connect() { this.update() }

  update() {
    this.weekdaysTarget.hidden = this.selectTarget.value !== "custom"
    this.dateTarget.hidden = this.selectTarget.value !== "once"
  }
}
