import { Controller } from "@hotwired/stimulus"

// サイドバーの当日の日付と現在時刻（v1.5）。10 秒ごとに確認し、分が変わったときだけ描画する（ちらつき防止）。
// 表示は端末のローカルではなく Asia/Tokyo 固定。秒は出さない。aria-live は付けない（毎分読み上げない）。
export default class extends Controller {
  static targets = [ "date", "time" ]

  connect() {
    this.last = null
    this.render()
    this.timer = setInterval(() => this.render(), 10000)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  render() {
    const parts = new Intl.DateTimeFormat("ja-JP", {
      timeZone: "Asia/Tokyo", year: "numeric", month: "numeric", day: "numeric", weekday: "short",
      hour: "2-digit", minute: "2-digit", hourCycle: "h23"
    }).formatToParts(new Date())
    const part = (type) => parts.find((p) => p.type === type)?.value || ""
    const month = part("month"), day = part("day"), weekday = part("weekday")
    const hour = part("hour"), minute = part("minute")
    const key = `${month}-${day} ${hour}:${minute}`
    if (key === this.last) return
    this.last = key

    if (this.hasDateTarget) this.dateTarget.textContent = `${month}月${day}日（${weekday}）`
    if (this.hasTimeTarget) {
      this.timeTarget.textContent = `${hour}:${minute}`
      this.timeTarget.dateTime =
        `${part("year")}-${month.padStart(2, "0")}-${day.padStart(2, "0")}T${hour}:${minute}:00+09:00`
    }
  }
}
