import { Controller } from "@hotwired/stimulus"
import { detectMarkings, paddedBox } from "lib/marking_detector"

// 赤枠でマーキングした教材画像の取り込み画面。
// ブラウザ側で ①長辺を縮小 ②赤枠を検出 ③プレビューで削除・調整・手動追加 ④縮小済みの元画像と切り出しだけをサーバーへ送る。
// 検出が外れても、領域を手動で追加すればそのまま進める（R6）。しきい値はサーバーから配る設定値（config）を使う。
export default class extends Controller {
  static targets = ["input", "drop", "items", "itemTemplate", "rowTemplate", "confirm", "status", "generateAnswers"]
  static values = { config: Object, url: String }

  connect() {
    this.items = []
    this.nextId = 1
    this.updateConfirm()
  }

  disconnect() {
    this.items.forEach((item) => URL.revokeObjectURL(item.objectUrl))
  }

  // --- 画像の受け取り ---
  pick() { this.addFiles(this.inputTarget.files); this.inputTarget.value = "" }
  dragover(e) { e.preventDefault(); this.dropTarget.dataset.dragging = "true" }
  dragleave() { delete this.dropTarget.dataset.dragging }
  drop(e) {
    e.preventDefault(); delete this.dropTarget.dataset.dragging
    this.addFiles(e.dataTransfer.files)
  }

  async addFiles(fileList) {
    const files = [...fileList].filter((f) => /^image\/(jpeg|png)$/.test(f.type))
    if (files.length < fileList.length) this.say("JPEG か PNG だけ取り込めます。ほかの形式は無視しました。")
    for (const file of files) {
      const item = { id: this.nextId++, name: file.name, regions: [], saved: false, busy: true }
      this.items.push(item)
      this.buildCard(item)
      this.setState(item, "読み込み中…")
      try {
        await this.prepare(item, file)
        item.regions = detectMarkings(item.imageData, this.configValue.detector).map((r) => this.newRegion(r))
        delete item.imageData
        this.setState(item, item.regions.length ? `赤枠を ${item.regions.length} 件検出しました` : "赤枠が見つかりませんでした。「領域を追加」で手動で囲めます。")
      } catch (error) {
        item.failed = true
        this.setState(item, `読み込めませんでした（${error.message}）`)
      }
      item.busy = false
      this.render(item)
      this.updateConfirm()
    }
  }

  // 長辺を maxLongSide に縮小し、上限サイズに収まる JPEG にする
  async prepare(item, file) {
    const bitmap = await createImageBitmap(file, { imageOrientation: "from-image" })
    const longSide = Math.max(bitmap.width, bitmap.height)
    let scale = Math.min(1, this.configValue.maxLongSide / longSide)
    let blob, canvas
    for (let attempt = 0; attempt < 6; attempt++) {
      canvas = document.createElement("canvas")
      canvas.width = Math.max(1, Math.round(bitmap.width * scale))
      canvas.height = Math.max(1, Math.round(bitmap.height * scale))
      const ctx = canvas.getContext("2d", { willReadFrequently: true })
      ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, canvas.width, canvas.height)
      ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height)
      blob = await toBlob(canvas, "image/jpeg", this.configValue.jpegQuality)
      if (blob.size <= this.configValue.maxBytes) break
      scale *= 0.8 // 上限を超えるときは、さらに縮小する
    }
    bitmap.close?.()
    if (blob.size > this.configValue.maxBytes) throw new Error("縮小しても上限を超えます")
    Object.assign(item, { blob, canvas, width: canvas.width, height: canvas.height })
    item.imageData = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height)
    item.objectUrl = URL.createObjectURL(blob)
  }

  newRegion({ x, y, w, h, confidence = null, angle = 0, manual = false }) {
    return { id: this.nextId++, x: Math.round(x), y: Math.round(y), w: Math.round(w), h: Math.round(h), confidence, angle, manual }
  }

  // --- カード（1枚ぶんのプレビュー） ---
  buildCard(item) {
    const card = this.itemTemplateTarget.content.firstElementChild.cloneNode(true)
    item.el = card
    card.dataset.itemId = item.id
    card.querySelector("[data-name]").textContent = item.name
    card.querySelector("[data-add]").addEventListener("click", () => this.addRegion(item))
    const overlay = card.querySelector("[data-overlay]")
    overlay.addEventListener("pointerdown", (e) => { if (e.target === overlay) this.startDraw(e, item) })
    this.itemsTarget.append(card)
  }

  setState(item, text) { item.el.querySelector("[data-state]").textContent = text }

  render(item) {
    if (item.failed) return
    const img = item.el.querySelector("[data-image]")
    if (img.getAttribute("src") !== item.objectUrl) img.src = item.objectUrl
    this.renderOverlay(item)
    this.renderRows(item)
  }

  renderOverlay(item) {
    const overlay = item.el.querySelector("[data-overlay]")
    overlay.replaceChildren()
    item.regions.forEach((region, index) => {
      const box = document.createElement("div")
      box.dataset.box = region.id
      box.className = "absolute border-2 border-ng bg-ng/10 cursor-move"
      Object.assign(box.style, this.boxStyle(item, region))
      const tag = document.createElement("span")
      tag.className = "absolute -top-6 left-0 rounded bg-ng px-1.5 text-xs font-bold text-white"
      tag.textContent = String(index + 1)
      const handle = document.createElement("span")
      handle.className = "absolute -bottom-2 -right-2 size-4 rounded-full border-2 border-white bg-ng cursor-nwse-resize"
      handle.dataset.handle = ""
      box.append(tag, handle)
      box.addEventListener("pointerdown", (e) => { e.stopPropagation(); this.startDrag(e, item, region, e.target === handle ? "resize" : "move") })
      overlay.append(box)
    })
  }

  boxStyle(item, r) {
    return { left: `${(r.x / item.width) * 100}%`, top: `${(r.y / item.height) * 100}%`, width: `${(r.w / item.width) * 100}%`, height: `${(r.h / item.height) * 100}%` }
  }

  renderRows(item) {
    const list = item.el.querySelector("[data-regions]")
    list.replaceChildren()
    item.regions.forEach((region, index) => {
      const row = this.rowTemplateTarget.content.firstElementChild.cloneNode(true)
      row.dataset.regionRow = region.id
      row.querySelector("[data-number]").textContent = `領域 ${index + 1}`
      row.querySelector("[data-source]").textContent = region.manual ? "手動" : `自動 ${Math.round((region.confidence ?? 0) * 100)}%`
      for (const key of ["x", "y", "w", "h"]) {
        const input = row.querySelector(`[data-field="${key}"]`)
        input.value = region[key]
        input.setAttribute("aria-label", `領域 ${index + 1} の ${{ x: "左", y: "上", w: "幅", h: "高さ" }[key]}`)
        input.addEventListener("input", () => this.setField(item, region, key, input))
      }
      row.querySelector("[data-delete]").setAttribute("aria-label", `領域 ${index + 1} を削除`)
      row.querySelector("[data-delete]").addEventListener("click", () => this.removeRegion(item, region))
      list.append(row)
    })
    item.el.querySelector("[data-empty]").hidden = item.regions.length > 0
  }

  // --- 領域の編集 ---
  setField(item, region, key, input) {
    const value = Math.round(Number(input.value))
    if (!Number.isFinite(value)) return
    region[key] = value
    this.clamp(item, region)
    this.renderOverlay(item)
  }

  clamp(item, r) {
    r.w = Math.max(8, Math.min(r.w, item.width)); r.h = Math.max(8, Math.min(r.h, item.height))
    r.x = Math.max(0, Math.min(r.x, item.width - r.w)); r.y = Math.max(0, Math.min(r.y, item.height - r.h))
  }

  addRegion(item) {
    const w = Math.round(item.width * 0.4), h = Math.round(item.height * 0.25)
    item.regions.push(this.newRegion({ x: (item.width - w) / 2, y: (item.height - h) / 2, w, h, manual: true }))
    this.render(item); this.updateConfirm()
  }

  removeRegion(item, region) {
    item.regions = item.regions.filter((r) => r.id !== region.id)
    this.render(item); this.updateConfirm()
  }

  toImagePoint(item, e) {
    const rect = item.el.querySelector("[data-overlay]").getBoundingClientRect()
    return { x: ((e.clientX - rect.left) / rect.width) * item.width, y: ((e.clientY - rect.top) / rect.height) * item.height }
  }

  startDrag(e, item, region, mode) {
    e.preventDefault()
    const start = this.toImagePoint(item, e)
    const origin = { ...region }
    const move = (ev) => {
      const p = this.toImagePoint(item, ev)
      if (mode === "move") { region.x = Math.round(origin.x + p.x - start.x); region.y = Math.round(origin.y + p.y - start.y) }
      else { region.w = Math.round(origin.w + p.x - start.x); region.h = Math.round(origin.h + p.y - start.y) }
      this.clamp(item, region)
      this.renderOverlay(item); this.syncRow(item, region)
    }
    this.trackPointer(move)
  }

  // 何もない所をドラッグして、手動で領域を追加する
  startDraw(e, item) {
    e.preventDefault()
    const start = this.toImagePoint(item, e)
    const region = this.newRegion({ x: start.x, y: start.y, w: 1, h: 1, manual: true })
    item.regions.push(region)
    const move = (ev) => {
      const p = this.toImagePoint(item, ev)
      region.x = Math.round(Math.min(start.x, p.x)); region.y = Math.round(Math.min(start.y, p.y))
      region.w = Math.round(Math.abs(p.x - start.x)); region.h = Math.round(Math.abs(p.y - start.y))
      this.renderOverlay(item)
    }
    this.trackPointer(move, () => {
      if (region.w < 12 || region.h < 12) item.regions = item.regions.filter((r) => r.id !== region.id) // 小さすぎるドラッグは無視
      else this.clamp(item, region)
      this.render(item); this.updateConfirm()
    })
  }

  trackPointer(move, done) {
    const up = () => {
      window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up)
      done?.()
    }
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up)
  }

  syncRow(item, region) {
    const row = item.el.querySelector(`[data-region-row="${region.id}"]`)
    if (!row) return
    for (const key of ["x", "y", "w", "h"]) row.querySelector(`[data-field="${key}"]`).value = region[key]
  }

  // --- 保存 ---
  updateConfirm() {
    const ready = this.items.filter((i) => !i.saved && !i.failed && !i.busy && i.regions.length > 0)
    this.confirmTarget.disabled = ready.length === 0 || this.saving
  }

  async confirmAll() {
    this.saving = true; this.updateConfirm()
    let saved = 0, failed = 0
    for (const item of this.items.filter((i) => !i.saved && !i.failed && i.regions.length > 0)) {
      this.setState(item, "保存中…")
      try {
        const result = await this.upload(item)
        item.saved = true; saved++
        item.el.dataset.saved = "true"
        this.setState(item, result.duplicate ? "取り込み済みの画像でした（既存のデータを使います）" : `保存しました（領域 ${result.regions} 件）`)
        item.el.querySelectorAll("button, input").forEach((el) => (el.disabled = true))
      } catch (error) {
        failed++
        this.setState(item, `保存できませんでした：${error.message}`)
      }
    }
    this.saving = false; this.updateConfirm()
    this.say(failed ? `${saved} 枚を保存、${failed} 枚は保存できませんでした。` : `${saved} 枚を保存しました。`)
  }

  async upload(item) {
    const form = new FormData()
    form.append("image", item.blob, "image.jpg")
    form.append("width", item.width)
    form.append("height", item.height)
    form.append("generate_answers", this.hasGenerateAnswersTarget && !this.generateAnswersTarget.checked ? "0" : "1")
    for (const [index, region] of item.regions.entries()) {
      const crop = await this.crop(item, region)
      form.append(`regions[${index}][bbox]`, JSON.stringify({ x: region.x, y: region.y, w: region.w, h: region.h, angle: region.angle, manual: region.manual }))
      if (region.confidence != null) form.append(`regions[${index}][confidence]`, region.confidence)
      form.append(`regions[${index}][image]`, crop, `region-${index}.jpg`)
    }
    const response = await fetch(this.urlValue, {
      method: "POST", body: form, headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content, Accept: "application/json" }
    })
    const body = await response.json().catch(() => ({}))
    if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`)
    return body
  }

  // 余白（MARKING_CROP_PADDING、既定 4px）つきで切り出す。傾きが検出されていれば、傾きを補正して回す
  crop(item, region) {
    const box = paddedBox(region, item.width, item.height, this.configValue.padding)
    const canvas = document.createElement("canvas")
    canvas.width = box.w; canvas.height = box.h
    const ctx = canvas.getContext("2d")
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, box.w, box.h)
    if (region.angle) {
      ctx.translate(box.w / 2, box.h / 2)
      ctx.rotate((-region.angle * Math.PI) / 180)
      ctx.drawImage(item.canvas, -(box.x + box.w / 2), -(box.y + box.h / 2))
    } else {
      ctx.drawImage(item.canvas, box.x, box.y, box.w, box.h, 0, 0, box.w, box.h)
    }
    return toBlob(canvas, "image/jpeg", this.configValue.jpegQuality)
  }

  say(text) { this.statusTarget.textContent = text }
}

const toBlob = (canvas, type, quality) =>
  new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("画像を作れませんでした"))), type, quality))
