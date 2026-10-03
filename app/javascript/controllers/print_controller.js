import { Controller } from "@hotwired/stimulus"

// 問題のみ／解答のみ／問題と解答 を切り替えて印刷する。
// 「問題と解答」は1回の印刷で問題→解答の順に出す（両面印刷はしない。用紙は別々の1枚）
export default class extends Controller {
  static targets = [ "kind", "sheet", "sheets" ]

  connect() {
    this.choose()
  }

  choose() {
    const kind = this.kindTarget.value
    this.sheetTargets.forEach((sheet) => {
      sheet.hidden = !(kind === "both" || sheet.dataset.kind === kind)
    })
    this.sheetsTarget.dataset.mode = kind
  }

  print() {
    window.print()
  }
}
