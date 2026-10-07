import { Controller } from "@hotwired/stimulus"

// 日付のボタンを押すと、アプリ内の月カレンダー（ポップオーバー）を開き、選んだ日の画面へ移る（GET の date パラメータ）。
// ブラウザ標準の input type=date には頼らない。Esc・外側クリックで閉じる。矢印キーで日を移動、Enter で決定。
export default class extends Controller {
  static targets = [ "input", "button", "panel", "title", "grid" ]
  static values = { selected: String, today: String }

  connect() {
    this.outside = (event) => { if (!this.element.contains(event.target)) this.close() }
    this.month = this.parse(this.selectedValue)
    this.month.setDate(1)
  }

  disconnect() { document.removeEventListener("click", this.outside) }

  toggle() { this.panelTarget.hidden ? this.open() : this.close() }

  open() {
    this.month = this.parse(this.selectedValue)
    this.month.setDate(1)
    this.render()
    this.panelTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    document.addEventListener("click", this.outside)
    this.focusDay(this.selectedValue) || this.focusDay(this.todayValue) || this.gridTarget.querySelector("button[data-date]")?.focus()
  }

  close() {
    if (this.panelTarget.hidden) return
    this.panelTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
    document.removeEventListener("click", this.outside)
  }

  prevMonth() { this.month.setMonth(this.month.getMonth() - 1); this.render() }
  nextMonth() { this.month.setMonth(this.month.getMonth() + 1); this.render() }

  choose(event) {
    this.inputTarget.value = event.currentTarget.dataset.date
    this.element.requestSubmit()
  }

  keydown(event) {
    if (event.key === "Escape") {
      event.stopPropagation()
      this.close()
      this.buttonTarget.focus()
      return
    }
    const day = event.target.closest("button[data-date]")
    const step = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[event.key]
    if (!day || !step) return
    event.preventDefault()
    const next = this.parse(day.dataset.date)
    next.setDate(next.getDate() + step)
    if (next.getMonth() !== this.month.getMonth() || next.getFullYear() !== this.month.getFullYear()) {
      this.month = new Date(next.getFullYear(), next.getMonth(), 1)
      this.render()
    }
    this.focusDay(this.format(next))
  }

  render() {
    const y = this.month.getFullYear(), m = this.month.getMonth()
    this.titleTarget.textContent = `${y}年${m + 1}月`
    const lead = this.month.getDay()
    const days = new Date(y, m + 1, 0).getDate()
    const cells = []
    for (let i = 0; i < lead; i++) cells.push(`<span></span>`)
    for (let d = 1; d <= days; d++) {
      const iso = this.format(new Date(y, m, d))
      const selected = iso === this.selectedValue
      const today = iso === this.todayValue
      const cls = selected ? "bg-primary text-white font-bold" : today ? "ring-2 ring-primary font-bold hover:bg-bg" : "hover:bg-bg"
      cells.push(`<button type="button" data-date="${iso}" data-action="date-jump#choose" class="h-11 min-w-11 rounded-field text-base tnum ${cls}"${selected ? ' aria-current="date"' : ""} aria-label="${m + 1}月${d}日${today ? "（今日）" : ""}">${d}</button>`)
    }
    this.gridTarget.innerHTML = cells.join("")
  }

  focusDay(iso) {
    const el = this.gridTarget.querySelector(`button[data-date="${iso}"]`)
    el?.focus()
    return !!el
  }

  parse(iso) {
    const [ y, m, d ] = iso.split("-").map(Number)
    return new Date(y, m - 1, d)
  }

  format(date) {
    const p = (n) => String(n).padStart(2, "0")
    return `${date.getFullYear()}-${p(date.getMonth() + 1)}-${p(date.getDate())}`
  }
}
