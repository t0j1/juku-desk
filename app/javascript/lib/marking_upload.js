import { detectMarkings, paddedBox } from "lib/marking_detector"

// マーキング画像を、縮小 → 赤枠検出 → 切り出し → POST /marking まで運ぶ部品（問題フォルダ画面の「ファイルを選ぶ」用）。
// marking_controller.js（プレビューで手直しする取り込み画面）と同じ流れ・同じ設定値（config）を、プレビューなしで使う。

export const toBlob = (canvas, type, quality) =>
  new Promise((resolve, reject) => canvas.toBlob((b) => (b ? resolve(b) : reject(new Error("画像を作れませんでした"))), type, quality))

// 描ける物（ImageBitmap / canvas）を、長辺 maxLongSide に縮小し、上限サイズに収まる JPEG にする
export async function prepareImage(source, config) {
  const longSide = Math.max(source.width, source.height)
  let scale = Math.min(1, config.maxLongSide / longSide)
  let blob, canvas
  for (let attempt = 0; attempt < 6; attempt++) {
    canvas = document.createElement("canvas")
    canvas.width = Math.max(1, Math.round(source.width * scale))
    canvas.height = Math.max(1, Math.round(source.height * scale))
    const ctx = canvas.getContext("2d", { willReadFrequently: true })
    ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, canvas.width, canvas.height)
    ctx.drawImage(source, 0, 0, canvas.width, canvas.height)
    blob = await toBlob(canvas, "image/jpeg", config.jpegQuality)
    if (blob.size <= config.maxBytes) break
    scale *= 0.8
  }
  if (blob.size > config.maxBytes) throw new Error("縮小しても上限を超えます")
  const imageData = canvas.getContext("2d").getImageData(0, 0, canvas.width, canvas.height)
  return { blob, canvas, width: canvas.width, height: canvas.height, imageData }
}

export function detectRegions(item, config) {
  return detectMarkings(item.imageData, config.detector).map((r) => ({
    x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.w), h: Math.round(r.h),
    confidence: r.confidence ?? null, angle: r.angle ?? 0, manual: false
  }))
}

function cropRegion(item, region, config) {
  const box = paddedBox(region, item.width, item.height, config.padding)
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
  return toBlob(canvas, "image/jpeg", config.jpegQuality)
}

// 1 枚ぶんを送る。folderId があれば、サーバーが取り込み後（重複で既存が返った場合も）そのフォルダに入れる
export async function uploadItem(item, regions, config, { url, folderId }) {
  const form = new FormData()
  form.append("image", item.blob, "image.jpg")
  form.append("width", item.width)
  form.append("height", item.height)
  if (folderId) form.append("folder_id", folderId)
  for (const [index, region] of regions.entries()) {
    const crop = await cropRegion(item, region, config)
    form.append(`regions[${index}][bbox]`, JSON.stringify({ x: region.x, y: region.y, w: region.w, h: region.h, angle: region.angle, manual: region.manual }))
    if (region.confidence != null) form.append(`regions[${index}][confidence]`, region.confidence)
    form.append(`regions[${index}][image]`, crop, `region-${index}.jpg`)
  }
  const response = await fetch(url, {
    method: "POST", body: form, headers: { "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content, Accept: "application/json" }
  })
  const body = await response.json().catch(() => ({}))
  if (!response.ok) throw new Error(body.error || `HTTP ${response.status}`)
  return body
}
