import { Controller } from "@hotwired/stimulus"

// 日付の表示を押すと、ブラウザ標準のカレンダー（input type=date）を開き、選んだ日の画面へ移る（GET の date パラメータ）。
// 月の移動・今日の強調・Esc／外側クリックで閉じる動きはブラウザのカレンダーが受け持つ。
export default class extends Controller {
  static targets = [ "input" ]

  open() {
    if (this.inputTarget.showPicker) this.inputTarget.showPicker()
    else this.inputTarget.focus()
  }

  // 日を選んだら移動する（空にされたときは何もしない）
  go() {
    if (this.inputTarget.value) this.element.requestSubmit()
  }
}
