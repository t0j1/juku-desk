import { Controller } from "@hotwired/stimulus"

// 小テスト印刷画面で、解答欄の広さ・小問番号・ページ内の配置を、印刷前に切り替える（この画面を開いている間だけ有効。保存はしない）。
// 配置: top=上詰め（従来）／even=ページ内に等間隔／count=1ページあたりの問題数を指定。
// 問題を 1 ページ分ずつの <ol> に分けて並べ直す（問題の途中ではページを切らない）。A4 縦・余白 15mm なので、1 ページの高さは 267mm。
const PAGE_HEIGHT_MM = 267
const ITEM_GAP_MM = 6

export default class extends Controller {
  static targets = [ "sheet", "size", "numbering", "numberingJob", "layout", "count", "countField" ]

  connect() {
    this.lists = Array.from(this.sheetTarget.querySelectorAll(".mt-list")).map((list) => ({ list, items: Array.from(list.children) }))
    this.apply()
    // フォントや数式の描画で問題の高さが変わるので、描画後と印刷の直前にもう一度並べ直す
    this.reapply = () => this.apply()
    document.fonts?.ready.then(() => requestAnimationFrame(this.reapply))
    window.addEventListener("beforeprint", this.reapply)
  }

  disconnect() { window.removeEventListener("beforeprint", this.reapply) }

  apply() {
    this.sheetTarget.dataset.answerSize = this.sizeTarget.value
    this.renumber()
    this.countFieldTarget.hidden = this.layoutTarget.value !== "count"
    this.reset()
    if (this.layoutTarget.value !== "top") this.paginate()
  }

  // 小問番号：original=元のまま／per=大問ごとに(1)から／cont=通しで(1)から（番号の対応はサーバーが span の data に入れている）
  renumber() {
    const mode = this.numberingTarget.value
    // 印刷ジョブ（PDF）へ渡す値も、このセレクトと同じにする
    if (this.hasNumberingJobTarget) this.numberingJobTarget.value = mode
    this.sheetTarget.querySelectorAll(".mt-subno").forEach((span) => {
      const n = mode === "original" ? null : span.dataset[mode]
      span.textContent = n ? `${span.dataset.original.match(/^\s*/)[0]}(${n})` : span.dataset.original
    })
  }

  mm(value) {
    const probe = document.createElement("div")
    probe.style.cssText = `position:absolute;visibility:hidden;height:${value}mm`
    this.sheetTarget.appendChild(probe)
    const px = probe.getBoundingClientRect().height
    probe.remove()
    return px
  }

  reset() {
    this.sheetTarget.querySelectorAll("ol.mt-page").forEach((ol) => ol.remove())
    this.lists.forEach(({ list, items }) => items.forEach((item) => list.appendChild(item)))
  }

  paginate() {
    const even = this.layoutTarget.value === "even"
    const perPage = Math.max(1, parseInt(this.countTarget.value, 10) || 1)
    const pageH = this.mm(PAGE_HEIGHT_MM)
    const gap = this.mm(ITEM_GAP_MM)
    const sheetTop = this.sheetTarget.querySelector(".mt-head").getBoundingClientRect().top
    const pages = []

    this.lists.forEach(({ list, items }, index) => {
      // 1 ページ目に入る高さ：先頭の大問は用紙の上から、次の大問からは新しいページの見出しの下から
      const above = index === 0 ? list.getBoundingClientRect().top - sheetTop : (list.getBoundingClientRect().top - (list.closest(".mt-section") || list).getBoundingClientRect().top)
      let groups = []
      if (even) {
        let current = [], used = 0, cap = pageH - above
        items.forEach((item) => {
          const h = item.getBoundingClientRect().height + gap
          if (current.length && used + h > cap) { groups.push({ items: current, cap }); current = []; used = 0; cap = pageH }
          current.push(item); used += h
        })
        if (current.length) groups.push({ items: current, cap })
      } else {
        for (let i = 0; i < items.length; i += perPage) groups.push({ items: items.slice(i, i + perPage) })
      }
      let after = list
      groups.forEach((group) => {
        const ol = document.createElement("ol")
        ol.className = "mt-list mt-page"
        if (even) { ol.dataset.even = ""; ol.style.minHeight = `${group.cap}px` }
        group.items.forEach((item) => ol.appendChild(item))
        after.after(ol)
        after = ol
        pages.push(ol)
      })
    })
    pages.slice(0, -1).forEach((ol) => ol.classList.add("mt-page-break"))
  }
}
