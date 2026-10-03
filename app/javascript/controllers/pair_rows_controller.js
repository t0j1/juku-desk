import { Controller } from "@hotwired/stimulus"

// 「回を追加」で問題と解答の入力行を1組ずつ増やす
export default class extends Controller {
  static targets = [ "body", "template" ]

  add(event) {
    event.preventDefault()
    const used = Array.from(this.bodyTarget.querySelectorAll("tr")).map((tr) => {
      const m = (tr.querySelector("input")?.value || "").match(/第\s*(\d+)\s*回/)
      return m ? Number(m[1]) : 0
    })
    const index = Math.max(this.bodyTarget.querySelectorAll("tr").length, ...used) + 1
    const html = this.templateTarget.innerHTML.replaceAll("__N__", index)
    this.bodyTarget.insertAdjacentHTML("beforeend", html)
  }

  remove(event) {
    event.preventDefault()
    event.target.closest("tr").remove()
  }
}
