import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// 進捗モーダルの処理（progress:finished）が自分の対象のものだったら、画面を読み直して次の状態に進む。
// 「進み具合を見る」はレイアウト側の進捗モーダルを開く（progress:open）
export default class extends Controller {
  static values = { subjectId: Number }

  reload(event) {
    if (event.detail.subject_id !== this.subjectIdValue) return
    Turbo.visit(window.location.href, { action: "replace" })
  }

  open() { window.dispatchEvent(new CustomEvent("progress:open")) }
}
