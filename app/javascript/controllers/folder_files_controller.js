import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"
import { prepareImage, detectRegions, uploadItem } from "lib/marking_upload"

// 問題フォルダ画面で、端末のファイル（JPEG / PNG / PDF）やカメラの写真を直接入れる。
// 画像は縮小・赤枠検出して POST /marking（既存の取り込みと同じ）へ送り、サーバーがそのフォルダに入れる。
// PDF はこのブラウザで pdf.js により 1 ページずつ画像にして同じ流れに載せる（サーバーは PDF を解析しない）。
// 超過・非対応・壊れた/暗号化 PDF・読めないページは、ファイル/ページ単位で理由を出して、ほかは続ける。
export default class extends Controller {
  static targets = [ "input", "progress", "result" ]
  static values = { config: Object, url: String, folderId: String }

  connect() { this.showStoredSummary() }

  async pick() {
    const files = [ ...this.inputTarget.files ]
    this.inputTarget.value = ""
    if (files.length) await this.run(files)
  }

  async run(files) {
    const config = this.configValue
    const summary = { added: 0, duplicate: 0, noRegion: 0, failed: [] }
    const accepted = files.slice(0, config.maxFiles)
    files.slice(config.maxFiles).forEach((f) => summary.failed.push(`${f.name}：1 回に選べるのは ${config.maxFiles} ファイルまでです（超過分は取り込んでいません）`))
    this.inputTarget.disabled = true
    this.progress = { done: 0, total: accepted.length }
    for (const file of accepted) {
      const kind = this.kindOf(file)
      try {
        if (kind === "image") await this.importImage(file, file.name, summary)
        else if (kind === "pdf") await this.importPdf(file, summary)
        else summary.failed.push(`${file.name}：JPEG・PNG・PDF 以外の形式は取り込めません`)
      } catch (error) {
        summary.failed.push(`${file.name}：${error.message}`)
      }
      if (kind !== "pdf") this.tick(file.name)
    }
    this.progressTarget.textContent = "完了しました。フォルダの表示を更新します…"
    sessionStorage.setItem(this.storageKey, JSON.stringify(summary))
    Turbo.visit(window.location.href, { action: "replace" })
  }

  kindOf(file) {
    if (/^image\/(jpeg|png)$/.test(file.type) || /\.(jpe?g|png)$/i.test(file.name)) return "image"
    if (file.type === "application/pdf" || /\.pdf$/i.test(file.name)) return "pdf"
    return null
  }

  tick(name) {
    this.progress.done++
    this.progressTarget.textContent = `取り込み中 ${Math.min(this.progress.done, this.progress.total)}/${this.progress.total}（${name}）`
  }

  async importImage(file, label, summary) {
    let bitmap
    try { bitmap = await createImageBitmap(file, { imageOrientation: "from-image" }) } catch { throw new Error("画像を読めませんでした") }
    try { await this.importSource(bitmap, label, summary) } finally { bitmap.close?.() }
  }

  // 描ける物 1 枚を、縮小・検出して送る
  async importSource(source, label, summary) {
    const item = await prepareImage(source, this.configValue)
    const regions = detectRegions(item, this.configValue)
    let body
    try { body = await uploadItem(item, regions, this.configValue, { url: this.urlValue, folderId: this.folderIdValue }) } catch (error) { throw new Error(`保存できませんでした（${error.message}）`) }
    if (!body.folder) throw new Error("フォルダに入れられませんでした（書き込み権限がありません）")
    if (body.duplicate) summary.duplicate++
    else summary.added++
    if (!body.duplicate && regions.length === 0) summary.noRegion++ // 赤枠なし：サーバーがページ全体を 1 領域にして保存する
  }

  async importPdf(file, summary) {
    const config = this.configValue
    if (file.size > config.pdfMaxBytes) {
      summary.failed.push(`${file.name}：PDF は 1 ファイル ${Math.round(config.pdfMaxBytes / 1048576)}MB までです`)
      return this.tick(file.name)
    }
    let pdf, task
    try {
      const pdfjs = await import("pdfjs")
      pdfjs.GlobalWorkerOptions.workerSrc = import.meta.resolve("pdfjs-worker")
      task = pdfjs.getDocument({ data: new Uint8Array(await file.arrayBuffer()) })
      pdf = await task.promise
    } catch (error) {
      task?.destroy()
      summary.failed.push(`${file.name}：${error.name === "PasswordException" ? "パスワード付き（暗号化）の PDF は取り込めません" : "PDF を読めませんでした（壊れている可能性があります）"}`)
      return this.tick(file.name)
    }
    if (pdf.numPages > config.pdfMaxPages) {
      summary.failed.push(`${file.name}：PDF は ${config.pdfMaxPages} ページまでです（${pdf.numPages} ページ）`)
      await task.destroy()
      return this.tick(file.name)
    }
    this.progress.total += pdf.numPages - 1 // この PDF は 1 ファイルではなくページ数ぶん数える
    for (let n = 1; n <= pdf.numPages; n++) {
      const label = `${file.name} ${n}/${pdf.numPages} ページ`
      try {
        const page = await pdf.getPage(n)
        const base = page.getViewport({ scale: 1 })
        const viewport = page.getViewport({ scale: config.maxLongSide / Math.max(base.width, base.height) })
        const canvas = document.createElement("canvas")
        canvas.width = Math.round(viewport.width); canvas.height = Math.round(viewport.height)
        await page.render({ canvasContext: canvas.getContext("2d"), viewport }).promise
        page.cleanup()
        await this.importSource(canvas, label, summary)
      } catch (error) {
        summary.failed.push(`${file.name} ${n} ページ目：${error.message || "読めませんでした"}`)
      }
      this.tick(label)
    }
    await task.destroy()
  }

  // --- 取り込み後の結果（ページを更新したあとに出す） ---
  get storageKey() { return `folderFilesSummary:${this.folderIdValue}` }

  showStoredSummary() {
    const raw = sessionStorage.getItem(this.storageKey)
    if (!raw) return
    sessionStorage.removeItem(this.storageKey)
    const s = JSON.parse(raw)
    const box = this.resultTarget
    box.replaceChildren()
    const line = (text, cls) => { const p = document.createElement("p"); p.className = cls; p.textContent = text; box.append(p) }
    line(`追加 ${s.added} 枚・重複 ${s.duplicate} 枚・失敗 ${s.failed.length} 件`, "text-lg font-bold " + (s.failed.length ? "text-err-fg" : "text-ok-fg"))
    if (s.duplicate) line("重複は取り込み済みの画像です。新しく作らず、そのままフォルダに入れました。", "text-lg text-text-sub")
    if (s.noRegion) line(`赤枠なし→ページ全体を読み取り：${s.noRegion} 枚（赤枠が見つからなかったので、画像全体を 1 つの領域にしました）。`, "text-lg text-text-sub")
    if (s.added) line("構造化は順次行います（Gemini 無料枠の上限を超えた分は翌日になります）。", "text-lg text-text-sub")
    if (s.failed.length) {
      const ul = document.createElement("ul"); ul.className = "list-disc pl-6 text-lg text-err-fg"; ul.dataset.failures = ""
      s.failed.forEach((t) => { const li = document.createElement("li"); li.textContent = t; ul.append(li) })
      box.append(ul)
    }
    box.hidden = false
  }
}
