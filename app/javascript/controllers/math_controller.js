import { Controller } from "@hotwired/stimulus"
import { renderMath } from "lib/math"

// 要素の中の $...$ / $$...$$ を数式として描画する（印刷画面・問題のレビュー一覧）
export default class extends Controller {
  connect() {
    renderMath(this.element)
  }
}
