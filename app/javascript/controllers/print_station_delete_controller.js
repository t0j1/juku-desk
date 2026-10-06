import { Controller } from "@hotwired/stimulus"

// 印刷ステーション削除確認モーダル
// 名前入力による誤削除防止（仕様 v1.7 §6-4-9）
export default class extends Controller {
  static targets = [ "modal", "input", "deleteButton", "cancelButton", "hint" ]
  static values = { stationName: String, stationId: String, isOnline: Boolean }

  connect() {
    this._boundOnKeydown = this._onKeydown.bind(this)
    this._boundOnClickOutside = this._onClickOutside.bind(this)
    this._boundOnInput = this._onInput.bind(this)
    this._boundOnCancel = this._onCancel.bind(this)
    this._boundOnDelete = this._onDelete.bind(this)

    this.modalTarget.addEventListener("keydown", this._boundOnKeydown)
    this.modalTarget.addEventListener("click", this._boundOnClickOutside)
    this.inputTarget.addEventListener("input", this._boundOnInput)
    this.cancelButtonTarget.addEventListener("click", this._boundOnCancel)
    this.deleteButtonTarget.addEventListener("click", this._boundOnDelete)
  }

  disconnect() {
    this.modalTarget.removeEventListener("keydown", this._boundOnKeydown)
    this.modalTarget.removeEventListener("click", this._boundOnClickOutside)
    this.inputTarget.removeEventListener("input", this._boundOnInput)
    this.cancelButtonTarget.removeEventListener("click", this._boundOnCancel)
    this.deleteButtonTarget.removeEventListener("click", this._boundOnDelete)
  }

  open(event) {
    // 元の削除ボタンを保存（閉じたときにフォーカスを戻すため）
    this._triggerButton = event.currentTarget
    this.modalTarget.style.display = "flex"
    this.inputTarget.focus()
    this._updateDeleteButton()
  }

  _onKeydown(event) {
    if (event.key === "Escape") {
      event.preventDefault()
      this._close()
    }
  }

  _onClickOutside(event) {
    // 背景クリックで閉じる（modal の backdrop 部分）
    if (event.target === this.modalTarget) {
      this._close()
    }
  }

  _onInput() {
    this._updateDeleteButton()
  }

  _onCancel() {
    this._close()
  }

  _onDelete() {
    if (!this.deleteButtonTarget.disabled) {
      // 隠しフォームを送信（既存の DELETE リクエストを送る）
      const form = document.getElementById(`delete_form_${this.stationIdValue}`)
      if (form) {
        form.requestSubmit()
      }
      this._close()
    }
  }

  _close() {
    this.modalTarget.style.display = "none"
    // 元の削除ボタンにフォーカスを戻す
    if (this._triggerButton) {
      this._triggerButton.focus()
    }
  }

  _updateDeleteButton() {
    const inputValue = this.inputTarget.value
    const normalizedInput = this._normalize(inputValue)
    const normalizedTarget = this._normalize(this.stationNameValue)
    const matches = normalizedInput === normalizedTarget

    this.deleteButtonTarget.disabled = !matches

    // ヒント文の切り替え
    if (matches) {
      this.hintTarget.textContent = "名前が一致しました。「削除する」を押すと削除されます。"
      this.hintTarget.classList.remove("text-text-sub")
      this.hintTarget.classList.add("text-ok-fg")
    } else {
      this.hintTarget.textContent = "名前が一致するまで「削除する」は押せません。"
      this.hintTarget.classList.remove("text-ok-fg")
      this.hintTarget.classList.add("text-text-sub")
    }
  }

  // 正規化：trim → 連続空白(全半角)を1つ → NFKC
  _normalize(str) {
    if (!str) return ""
    return str
      .trim()
      .replace(/[\s\u3000]+/g, " ")  // 連続する空白（半角・全角）を1つに
      .normalize("NFKC")             // 全角英数→半角英数
  }
}