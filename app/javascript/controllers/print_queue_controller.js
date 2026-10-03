import { Controller } from "@hotwired/stimulus"

// 印刷リスト。iPad のブラウザ（localStorage）に job ごとに保存する
export default class extends Controller {
  static targets = [ "list", "empty", "form", "count", "paperField", "paperNote", "neighborField", "neighbor" ]
  static values = { url: String, key: String, max: Number, labels: Object }

  connect() { this.render() }

  get items() {
    try { return JSON.parse(localStorage.getItem(this.keyValue) || "[]") } catch { return [] }
  }

  set items(v) {
    localStorage.setItem(this.keyValue, JSON.stringify(v))
    this.render()
  }

  // その回だけを新しいタブで開く（iPad の共有メニュー → プリント）
  printOne(event) {
    const row = event.target.closest("[data-round]")
    const item = `${row.dataset.round}:${row.querySelector("select").value}`
    const params = new URLSearchParams()
    params.append("items[]", item)
    if (this.hasPaperFieldTarget) params.append("paper", this.paperFieldTarget.value)
    if (this.hasNeighborFieldTarget) params.append("include_neighbor", this.neighborFieldTarget.value)
    window.open(`${this.urlValue}?${params}`, "_blank")
  }

  // 用紙（B4見開き / B5 / A4縮小）
  paper(event) {
    const btn = event.currentTarget
    this.element.querySelectorAll("[data-paper]").forEach((b) => b.setAttribute("aria-pressed", String(b === btn)))
    if (this.hasPaperFieldTarget) this.paperFieldTarget.value = btn.dataset.paper
    if (this.hasPaperNoteTarget) this.paperNoteTarget.textContent = btn.dataset.note
  }

  neighbor(event) {
    if (this.hasNeighborFieldTarget) this.neighborFieldTarget.value = event.currentTarget.checked ? "1" : "0"
  }

  add(event) {
    const row = event.target.closest("[data-round]")
    const round = row.dataset.round
    const kind = row.querySelector("select").value
    const items = this.items.filter((it) => it.round !== round)
    if (items.length >= this.maxValue) {
      alert(`まとめて印刷できるのは${this.maxValue}回分までです。`)
      return
    }
    items.push({ round, kind })
    this.items = items
  }

  remove(event) {
    const i = Number(event.target.closest("li").dataset.index)
    this.items = this.items.filter((_, j) => j !== i)
  }

  up(event) { this.move(event, -1) }
  down(event) { this.move(event, 1) }

  move(event, d) {
    const i = Number(event.target.closest("li").dataset.index)
    const items = this.items
    const j = i + d
    if (j < 0 || j >= items.length) return
    ;[ items[i], items[j] ] = [ items[j], items[i] ]
    this.items = items
  }

  clear() { this.items = [] }

  render() {
    const items = this.items
    this.listTarget.innerHTML = ""
    items.forEach((it, i) => {
      const li = document.createElement("li")
      li.dataset.index = i
      li.className = "flex items-center gap-2 py-1"
      const label = document.createElement("span")
      label.className = "flex-1"
      label.textContent = `${i + 1}. ${it.round} ${this.labelsValue[it.kind] || it.kind}`
      li.append(label)
      for (const [ text, action ] of [ [ "↑", "up" ], [ "↓", "down" ], [ "削除", "remove" ] ]) {
        const b = document.createElement("button")
        b.type = "button"
        b.textContent = text
        b.className = "rounded px-3 py-1 border"
        b.dataset.action = `print-queue#${action}`
        li.append(b)
      }
      this.listTarget.append(li)
    })
    this.emptyTarget.hidden = items.length > 0
    this.formTarget.hidden = items.length === 0
    this.countTarget.textContent = `${items.length} / ${this.maxValue}回分`
    this.formTarget.querySelectorAll("input[name='items[]']").forEach((el) => el.remove())
    items.forEach((it) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = "items[]"
      input.value = `${it.round}:${it.kind}`
      this.formTarget.append(input)
    })
  }
}
