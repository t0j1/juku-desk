import { Controller } from "@hotwired/stimulus"

// 解析中・分割中：軽い状態 JSON だけを数秒ごとに見て、状態が変わったら画面を読み直す。
// 画面がバックグラウンドのあいだは止める（Puma のスレッドを重いページの読み直しで埋めないため）
export default class extends Controller {
  static values = { url: String, current: String, interval: { type: Number, default: 5000 } }

  connect() {
    this.onVisibility = () => (document.hidden ? this.stop() : this.schedule())
    document.addEventListener("visibilitychange", this.onVisibility)
    this.schedule()
  }

  disconnect() {
    this.stop()
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  schedule() {
    this.stop()
    if (!document.hidden) this.timer = setTimeout(() => this.poll(), this.intervalValue)
  }

  stop() { clearTimeout(this.timer) }

  async poll() {
    try {
      const res = await fetch(`${this.urlValue}?t=${Date.now()}`, { headers: { Accept: "application/json" } })
      if (res.ok) {
        const { status } = await res.json()
        if (status !== this.currentValue) return window.Turbo ? Turbo.visit(window.location.href, { action: "replace" }) : window.location.reload()
      }
    } catch (_e) { /* 通信が切れても次の回で取り直す */ }
    this.schedule()
  }
}
