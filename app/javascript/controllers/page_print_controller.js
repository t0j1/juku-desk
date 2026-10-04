import { Controller } from "@hotwired/stimulus"

// 開いているページをそのまま印刷する（ブラウザの印刷ダイアログ。「PDF として保存」もここから）
export default class extends Controller {
  async print() {
    await document.fonts?.ready // KaTeX のフォントが読み込まれる前に印刷して崩れるのを防ぐ
    window.print()
  }
}
