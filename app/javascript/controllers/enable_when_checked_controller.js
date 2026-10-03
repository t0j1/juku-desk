import { Controller } from "@hotwired/stimulus"

// ラジオを1つ選ぶまで「次へ」を押せなくする
export default class extends Controller {
  static targets = [ "input", "button" ]

  connect() {
    this.update()
  }

  update() {
    this.buttonTarget.disabled = !this.inputTargets.some((input) => input.checked)
  }
}
