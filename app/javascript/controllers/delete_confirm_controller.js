import { Controller } from "@hotwired/stimulus"

// 名前を打たないと削除できないモーダル（<dialog>）。
// 比較は、前後の空白を除く → 連続する空白（全角・半角）を 1 つにする → NFKC の順で正規化した完全一致（大文字小文字は区別）
export default class extends Controller {
  static targets = [ "opener", "dialog", "input", "submit", "hint" ]
  static values = { name: String, matched: String, unmatched: String }

  open() {
    this.inputTarget.value = ""
    this.update()
    this.dialogTarget.showModal()
    this.inputTarget.focus()
  }

  cancel() {
    this.dialogTarget.close()
  }

  // Esc・キャンセル・背景クリックのどれで閉じても、元の「削除」ボタンへフォーカスを戻す
  closed() {
    this.openerTarget.focus()
  }

  // 背景（dialog 自身）のクリックだけを「閉じる」として扱う。中身のクリックは無視
  backdrop(event) {
    if (event.target === this.dialogTarget) this.cancel()
  }

  update() {
    const matched = this.normalize(this.inputTarget.value) === this.normalize(this.nameValue)
    this.submitTarget.disabled = !matched
    this.hintTarget.textContent = matched ? this.matchedValue : this.unmatchedValue
  }

  submit(event) {
    if (this.submitTarget.disabled) event.preventDefault()
  }

  normalize(text) {
    return text.trim().replace(/[\s　]+/g, " ").normalize("NFKC")
  }
}
