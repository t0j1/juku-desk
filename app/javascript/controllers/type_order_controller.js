import { Controller } from "@hotwired/stimulus"

// 「形式ごとに並べる」の形式の順番を、上へ・下へのボタンで入れ替える。順番は hidden の input にカンマ区切りで入れる
export default class extends Controller {
  static targets = [ "list", "input", "toggle", "panel" ]

  connect() {
    this.sync()
    this.toggled()
  }

  toggled() {
    if (this.hasToggleTarget && this.hasPanelTarget) this.panelTarget.hidden = !this.toggleTarget.checked
  }

  up(event) {
    event.preventDefault()
    const li = event.target.closest("li")
    if (li.previousElementSibling) li.parentNode.insertBefore(li, li.previousElementSibling)
    this.sync()
    event.target.closest("button")?.focus()
  }

  down(event) {
    event.preventDefault()
    const li = event.target.closest("li")
    if (li.nextElementSibling) li.parentNode.insertBefore(li.nextElementSibling, li)
    this.sync()
    event.target.closest("button")?.focus()
  }

  sync() {
    const items = Array.from(this.listTarget.querySelectorAll("li"))
    this.inputTarget.value = items.map((li) => li.dataset.type).join(",")
    items.forEach((li, i) => { li.querySelector("[data-order-no]").textContent = i + 1 })
  }
}
