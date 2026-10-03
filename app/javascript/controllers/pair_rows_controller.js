import { Controller } from "@hotwired/stimulus"

// 「回を追加」で問題と解答の入力行を1組ずつ増やす
export default class extends Controller {
  static targets = [ "body", "template" ]

  add(event) {
    event.preventDefault()
    const index = this.bodyTarget.querySelectorAll("tr").length + 1
    const html = this.templateTarget.innerHTML.replaceAll("__N__", index)
    this.bodyTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    event.target.closest("tr").remove()
  }
}
