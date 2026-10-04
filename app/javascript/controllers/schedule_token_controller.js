import { Controller } from "@hotwired/stimulus"

// iframe（schedule-web）の JWT を期限の前に差し替える。
// 新しいトークンは POST /schedule/token で取り、postMessage で iframe に渡す:
//   { type: "juku-desk:token", token: "<jwt>", exp: <unix 秒> }
// 401（ログアウト・セッション切断・ユーザー停止）なら更新をやめ、ページを読み込み直してログイン画面に戻す。
export default class extends Controller {
  static values = { url: String, origin: String, exp: Number }

  static LEAD_SECONDS = 60 // 期限のこの秒数前に更新する
  static RETRY_MS = 15_000

  connect() {
    this.schedule(this.expValue)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  schedule(exp) {
    const wait = Math.max(exp * 1000 - Date.now() - this.constructor.LEAD_SECONDS * 1000, 5_000)
    this.timer = setTimeout(() => this.refresh(), wait)
  }

  async refresh() {
    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content, Accept: "application/json" },
        credentials: "same-origin"
      })
      if (response.status === 401) return window.location.reload()
      if (!response.ok) throw new Error(`status ${response.status}`)
      const { token, exp } = await response.json()
      this.element.contentWindow.postMessage({ type: "juku-desk:token", token, exp }, this.originValue)
      this.schedule(exp)
    } catch {
      this.timer = setTimeout(() => this.refresh(), this.constructor.RETRY_MS)
    }
  }
}
