import { Controller } from "@hotwired/stimulus"

// 印刷ダイアログを開く（A4 の @page と print: スタイルは画面側で指定済み）
export default class extends Controller {
  print() {
    window.print()
  }
}
