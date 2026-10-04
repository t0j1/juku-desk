import { Controller } from "@hotwired/stimulus"

// 時間のかかる処理の進捗モーダルと、右上のバッジ。処理中のものがあるあいだだけ、数秒ごとに /progress を読む。
// 閉じても処理は続く。画面を移ってもレイアウトに載っているので、バッジから開き直せる。
export default class extends Controller {
  static targets = [ "badge", "badgeText", "dialog", "list", "item" ]
  static values = { url: String, ids: Array, open: Boolean, interval: { type: Number, default: 3000 } }

  connect() {
    this.items = new Map()
    this.dismissed = new Set()
    this.tick = setInterval(() => this.renderClock(), 1000)
    this.onVisibility = () => { if (!document.hidden) this.poll() }
    document.addEventListener("visibilitychange", this.onVisibility)
    if (this.idsValue.length) this.poll().then(() => { if (this.openValue) this.open() })
  }

  disconnect() {
    clearInterval(this.tick)
    clearTimeout(this.timer)
    document.removeEventListener("visibilitychange", this.onVisibility)
  }

  open() { if (!this.dialogTarget.open) this.dialogTarget.showModal() }
  close() { this.dialogTarget.close() }

  async cancel(event) {
    const li = event.target.closest("[data-progress-item]")
    event.target.disabled = true
    const res = await fetch(`${this.urlValue}/${li.dataset.id}/cancel`, { method: "POST", headers: this.headers() })
    if (res.ok) this.update(await res.json())
  }

  async poll() {
    clearTimeout(this.timer)
    if (document.hidden) return
    try {
      const res = await fetch(this.urlValue, { headers: { Accept: "application/json" } })
      if (res.ok) (await res.json()).progresses.forEach((p) => this.update(p))
    } catch (_) { /* 通信が切れても次の周期でやり直す */ }
    if ([ ...this.items.values() ].some((i) => !i.data.finished)) {
      this.timer = setTimeout(() => this.poll(), this.intervalValue)
    }
  }

  update(p) {
    if (this.dismissed.has(p.id)) return
    let item = this.items.get(p.id)
    if (!item) {
      const li = this.itemTarget.content.firstElementChild.cloneNode(true)
      li.dataset.id = p.id
      this.listTarget.appendChild(li)
      item = { li }
      this.items.set(p.id, item)
    }
    item.data = p
    item.fetchedAt = Date.now()
    this.render(item)
    this.renderBadge()
    if (p.finished && !(item.announced)) {
      item.announced = true
      this.element.dispatchEvent(new CustomEvent("progress:finished", { bubbles: true, detail: p }))
    }
  }

  render(item) {
    const { li, data: p } = item
    const f = (name) => li.querySelector(`[data-field="${name}"]`)
    f("title").textContent = p.title
    const bar = f("bar")
    if (p.percent === null || p.percent === undefined) {
      // total 不明：割合の代わりに、動いていることが分かる縞の動きを出す
      bar.style.width = p.finished ? "100%" : "40%"
      bar.classList.toggle("animate-pulse", !p.finished)
      f("percent").textContent = ""
    } else {
      bar.style.width = `${p.percent}%`
      bar.classList.remove("animate-pulse")
      f("percent").textContent = `${p.percent}%`
    }
    bar.parentElement.setAttribute("aria-valuenow", p.percent ?? "")
    f("message").textContent = this.statusText(p)
    f("cancel").hidden = p.finished
    f("cancel").disabled = p.cancel_requested
    if (p.cancel_requested && !p.finished) f("cancel").textContent = "キャンセルしています…"
    this.renderClock()
  }

  statusText(p) {
    if (p.status === "succeeded") return "完了しました"
    if (p.status === "failed") return `失敗しました${p.message ? `：${p.message}` : ""}`
    if (p.status === "cancelled") return "キャンセルしました"
    if (p.status === "queued") return "順番待ちです"
    return p.message || ""
  }

  // 経過時間は 1 秒ごとに手元で進める（サーバーへは数秒おきにしか聞かない）
  renderClock() {
    this.items.forEach((item) => {
      const p = item.data
      if (!p) return
      const extra = p.finished ? 0 : Math.floor((Date.now() - item.fetchedAt) / 1000)
      const elapsed = p.elapsed_seconds + extra
      const detail = item.li.querySelector('[data-field="detail"]')
      if (p.total) {
        const eta = p.eta_seconds === null ? "" : `　残り約 ${this.mmss(Math.max(p.eta_seconds - extra, 0))}`
        detail.textContent = `${p.done} / ${p.total} 件　経過 ${this.mmss(elapsed)}${p.finished ? "" : eta}`
      } else {
        detail.textContent = p.finished ? `経過 ${this.mmss(elapsed)}` : `処理中（経過 ${this.mmss(elapsed)}）`
      }
    })
  }

  renderBadge() {
    const running = [ ...this.items.values() ].filter((i) => !i.data.finished)
    this.badgeTarget.hidden = running.length === 0 && !this.dialogTarget.open
    this.badgeTextTarget.textContent = running.length > 1 ? `処理中 ${running.length}件` : "処理中"
  }

  mmss(s) { return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}` }

  headers() {
    return { Accept: "application/json", "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content }
  }
}
