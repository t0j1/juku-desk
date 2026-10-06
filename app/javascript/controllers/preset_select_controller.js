import { Controller } from "@hotwired/stimulus"

// ドライバー設定名のプルダウンで「新しく追加する」を選んだときだけ、新しい名前の入力欄を出す
export default class extends Controller {
  static targets = [ "select", "input" ]

  connect() { this.toggle() }

  toggle() {
    const adding = this.selectTarget.value === "__new__"
    this.inputTarget.hidden = !adding
    this.inputTarget.disabled = !adding
    if (adding) this.inputTarget.focus()
  }
}
