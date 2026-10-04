import { Controller } from "@hotwired/stimulus"

// 開いているページをそのまま印刷する（ブラウザの印刷ダイアログ。「PDF として保存」もここから）
export default class extends Controller {
  print() {
    window.print()
  }
}
