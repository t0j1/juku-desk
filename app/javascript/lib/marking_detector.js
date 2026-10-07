// 赤枠でマーキングされた教材画像から、枠の領域を検出する（ブラウザでも node でも動く純粋な JS。DOM 非依存）。
//
// 手順: GaussianBlur 5x5 → HSV（H 0-179 / S,V 0-255）→ 赤の2範囲を or → CLOSE 5x5 ×2 → OPEN 3x3 ×1
//       → 外側の輪郭（8連結成分の外接矩形）→ フィルタ → 入れ子・近接の統合 → IoU の重複除去 → 傾きの推定。
// しきい値はすべて options（サーバーから data 属性で配る設定値）で上書きできる。ここの値は既定値にすぎない。

export const DEFAULTS = {
  hueLow: 10, hueHigh: 170, minSaturation: 70, minValue: 50, // 赤は H 0-10 と 170-179
  closeKernel: 5, closeIterations: 2, openKernel: 3, openIterations: 1,
  minAreaRatio: 0.005, maxAreaRatio: 0.9, maxAspectRatio: 20, maxFillRatio: 0.95,
  maxInnerFillRatio: 0.3, // 枠は中が空いている。中央 70% の赤画素率がこれを超える塗りブロック（文字入りの見出しタブなど）は枠ではない
  edgeMargin: 4,          // 画像の端とみなす距離（px）
  tabAspectRatio: 3,      // 端に接し、端に沿って細長い（縦横比がこれ以上）ブロックは、見出しタブとして除外する
  mergeGap: 12,        // 近接とみなす枠どうしの隙間（px）
  iouThreshold: 0.5,
  tiltThreshold: 0.5,  // これを超える傾き（度）だけ補正対象にする
  tiltSearch: 5        // 傾きを探す範囲（±度）
}

// image: { data: Uint8ClampedArray(RGBA), width, height }（ImageData と同じ形）
// 戻り値: [{ x, y, w, h, confidence, angle }]（confidence の高い順）
export function detectMarkings(image, options = {}) {
  const o = { ...DEFAULTS, ...options }
  const { width, height } = image
  const blurred = gaussianBlur5(image.data, width, height)
  let mask = redMask(blurred, width, height, o)
  mask = repeat(mask, width, height, o.closeKernel, o.closeIterations, dilate, erode)
  mask = repeat(mask, width, height, o.openKernel, o.openIterations, erode, dilate)

  const { labels, components } = label(mask, width, height)
  const imageArea = width * height
  let boxes = []
  for (const c of components) {
    const w = c.maxX - c.minX + 1
    const h = c.maxY - c.minY + 1
    const area = w * h
    if (area < imageArea * o.minAreaRatio || area > imageArea * o.maxAreaRatio) continue
    if (Math.max(w / h, h / w) > o.maxAspectRatio) continue
    if (c.count / area > o.maxFillRatio) continue // 塗りつぶし
    if (innerFillRatio(labels, width, c) > o.maxInnerFillRatio) continue // 枠ではない（中が詰まった塗りブロック）
    if (isEdgeTab(c, w, h, width, height, o)) continue // ページ端の細長いタブ
    boxes.push({ x: c.minX, y: c.minY, w, h, ids: [c.id] })
  }

  boxes = mergeBoxes(boxes, o.mergeGap)
  for (const b of boxes) b.confidence = edgeCoverage(mask, width, b)
  boxes = suppressOverlaps(boxes, o.iouThreshold)

  return boxes
    .map((b) => ({ x: b.x, y: b.y, w: b.w, h: b.h, confidence: round(b.confidence), angle: estimateTilt(labels, width, b, o) }))
    .sort((a, b) => b.confidence - a.confidence)
}

// 成分の外接矩形の中央 70% のうち、その成分の画素が占める割合。枠なら 0 に近く、塗りブロックは高い
function innerFillRatio(labels, width, c) {
  const w = c.maxX - c.minX + 1, h = c.maxY - c.minY + 1
  const x0 = c.minX + Math.floor(w * 0.15), x1 = c.maxX - Math.floor(w * 0.15)
  const y0 = c.minY + Math.floor(h * 0.15), y1 = c.maxY - Math.floor(h * 0.15)
  if (x1 < x0 || y1 < y0) return 0
  let n = 0
  for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) if (labels[y * width + x] === c.id) n++
  return n / ((x1 - x0 + 1) * (y1 - y0 + 1))
}

// 画像の左右の端に接して縦長、または上下の端に接して横長（端に沿って細長い）で、反対側の端には届かないもの
function isEdgeTab(c, w, h, width, height, o) {
  const m = o.edgeMargin
  const left = c.minX <= m, right = c.maxX >= width - 1 - m, top = c.minY <= m, bottom = c.maxY >= height - 1 - m
  if ((left !== right) && h / w >= o.tabAspectRatio) return true
  if ((top !== bottom) && w / h >= o.tabAspectRatio) return true
  return false
}

const round = (v) => Math.round(v * 1000) / 1000

function gaussianBlur5(rgba, width, height) {
  const k = [1, 4, 6, 4, 1]
  const tmp = new Float32Array(width * height * 3)
  const out = new Uint8ClampedArray(width * height * 3)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      for (let c = 0; c < 3; c++) {
        let s = 0
        for (let i = -2; i <= 2; i++) {
          const xx = Math.min(width - 1, Math.max(0, x + i))
          s += rgba[(y * width + xx) * 4 + c] * k[i + 2]
        }
        tmp[(y * width + x) * 3 + c] = s / 16
      }
    }
  }
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      for (let c = 0; c < 3; c++) {
        let s = 0
        for (let i = -2; i <= 2; i++) {
          const yy = Math.min(height - 1, Math.max(0, y + i))
          s += tmp[(yy * width + x) * 3 + c] * k[i + 2]
        }
        out[(y * width + x) * 3 + c] = s / 16
      }
    }
  }
  return out
}

function redMask(rgb, width, height, o) {
  const mask = new Uint8Array(width * height)
  for (let p = 0; p < mask.length; p++) {
    const r = rgb[p * 3], g = rgb[p * 3 + 1], b = rgb[p * 3 + 2]
    const max = Math.max(r, g, b), min = Math.min(r, g, b)
    if (max < o.minValue) continue
    const delta = max - min
    if (delta === 0 || (255 * delta) / max < o.minSaturation) continue
    let h
    if (max === r) h = (60 * (g - b)) / delta
    else if (max === g) h = 120 + (60 * (b - r)) / delta
    else h = 240 + (60 * (r - g)) / delta
    if (h < 0) h += 360
    h /= 2 // OpenCV の H は 0-179
    if (h <= o.hueLow || h >= o.hueHigh) mask[p] = 1
  }
  return mask
}

// 矩形カーネルの膨張・収縮（横 → 縦に分けて走査）。画像の外は、膨張では 0、収縮では 1 として扱う
function morph(mask, width, height, k, isDilate) {
  const r = (k - 1) >> 1
  const pad = isDilate ? 0 : 1
  const tmp = new Uint8Array(mask.length)
  const out = new Uint8Array(mask.length)
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let v = isDilate ? 0 : 1
      for (let i = -r; i <= r; i++) {
        const xx = x + i
        const m = xx < 0 || xx >= width ? pad : mask[y * width + xx]
        if (isDilate ? m : !m) { v = isDilate ? 1 : 0; break }
      }
      tmp[y * width + x] = v
    }
  }
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      let v = isDilate ? 0 : 1
      for (let i = -r; i <= r; i++) {
        const yy = y + i
        const m = yy < 0 || yy >= height ? pad : tmp[yy * width + x]
        if (isDilate ? m : !m) { v = isDilate ? 1 : 0; break }
      }
      out[y * width + x] = v
    }
  }
  return out
}
const dilate = (m, w, h, k) => morph(m, w, h, k, true)
const erode = (m, w, h, k) => morph(m, w, h, k, false)

// CLOSE = 膨張 → 収縮 / OPEN = 収縮 → 膨張。first, second の順に iterations 回ずつ
function repeat(mask, width, height, k, iterations, first, second) {
  let m = mask
  for (let i = 0; i < iterations; i++) m = first(m, width, height, k)
  for (let i = 0; i < iterations; i++) m = second(m, width, height, k)
  return m
}

// 8連結成分のラベリング（外側の輪郭 = 成分の外接矩形）
function label(mask, width, height) {
  const labels = new Int32Array(mask.length)
  const components = []
  const stack = []
  for (let start = 0; start < mask.length; start++) {
    if (!mask[start] || labels[start]) continue
    const id = components.length + 1
    const c = { id, minX: width, minY: height, maxX: 0, maxY: 0, count: 0 }
    labels[start] = id
    stack.push(start)
    while (stack.length) {
      const p = stack.pop()
      const x = p % width, y = (p / width) | 0
      c.count++
      if (x < c.minX) c.minX = x
      if (x > c.maxX) c.maxX = x
      if (y < c.minY) c.minY = y
      if (y > c.maxY) c.maxY = y
      for (let dy = -1; dy <= 1; dy++) {
        const yy = y + dy
        if (yy < 0 || yy >= height) continue
        for (let dx = -1; dx <= 1; dx++) {
          const xx = x + dx
          if (xx < 0 || xx >= width) continue
          const q = yy * width + xx
          if (mask[q] && !labels[q]) { labels[q] = id; stack.push(q) }
        }
      }
    }
    components.push(c)
  }
  return { labels, components }
}

const area = (b) => b.w * b.h
function intersection(a, b) {
  const w = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x)
  const h = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y)
  return w > 0 && h > 0 ? w * h : 0
}
const gapBetween = (a, b) => {
  const dx = Math.max(0, Math.max(a.x, b.x) - Math.min(a.x + a.w, b.x + b.w))
  const dy = Math.max(0, Math.max(a.y, b.y) - Math.min(a.y + a.h, b.y + b.h))
  return Math.max(dx, dy)
}
const contains = (a, b) => intersection(a, b) >= area(b) * 0.9 // b の 9 割以上が a に入っている（入れ子）

// 入れ子・近接（隙間が mergeGap 以下）の枠は、1つの外接矩形にまとめる
function mergeBoxes(boxes, gap) {
  let list = boxes.map((b) => ({ ...b }))
  let changed = true
  while (changed) {
    changed = false
    outer: for (let i = 0; i < list.length; i++) {
      for (let j = i + 1; j < list.length; j++) {
        const a = list[i], b = list[j]
        if (contains(a, b) || contains(b, a) || gapBetween(a, b) <= gap) {
          const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y)
          const x2 = Math.max(a.x + a.w, b.x + b.w), y2 = Math.max(a.y + a.h, b.y + b.h)
          list.splice(j, 1)
          list[i] = { x, y, w: x2 - x, h: y2 - y, ids: [...a.ids, ...b.ids] }
          changed = true
          break outer
        }
      }
    }
  }
  return list
}

// 枠の四辺のうち、赤が乗っている割合の平均（0-1）。きれいな枠ほど 1 に近い
function edgeCoverage(mask, width, b) {
  const band = Math.max(3, Math.round(Math.min(b.w, b.h) * 0.03))
  const at = (x, y) => mask[y * width + x]
  // 辺から内側へ band 画素のうち、どこかに赤があればその位置は「乗っている」
  const vertical = (x0, dir) => {
    let n = 0
    for (let y = b.y; y < b.y + b.h; y++) for (let d = 0; d < band; d++) if (at(x0 + dir * d, y)) { n++; break }
    return n / b.h
  }
  const horizontal = (y0, dir) => {
    let n = 0
    for (let x = b.x; x < b.x + b.w; x++) for (let d = 0; d < band; d++) if (at(x, y0 + dir * d)) { n++; break }
    return n / b.w
  }
  return (vertical(b.x, 1) + vertical(b.x + b.w - 1, -1) + horizontal(b.y, 1) + horizontal(b.y + b.h - 1, -1)) / 4
}

// IoU がしきい値を超える枠どうしは、confidence の高い方だけ残す
function suppressOverlaps(boxes, threshold) {
  const sorted = [...boxes].sort((a, b) => b.confidence - a.confidence)
  const kept = []
  for (const b of sorted) {
    const overlapping = kept.some((k) => {
      const inter = intersection(k, b)
      return inter / (area(k) + area(b) - inter) > threshold
    })
    if (!overlapping) kept.push(b)
  }
  return kept
}

// 成分の画素を ±tiltSearch 度で回し、外接矩形の面積が最小になる角度を傾きとする。しきい値以下なら 0
function estimateTilt(labels, width, b, o) {
  if (!b.ids) return 0
  const ids = new Set(b.ids)
  const stride = Math.max(1, Math.floor(Math.max(b.w, b.h) / 200))
  const points = []
  for (let y = b.y; y < b.y + b.h; y += stride) {
    for (let x = b.x; x < b.x + b.w; x += stride) {
      if (ids.has(labels[y * width + x])) points.push(x, y)
    }
  }
  if (!points.length) return 0
  let best = 0
  let bestArea = Infinity
  for (let deg = -o.tiltSearch; deg <= o.tiltSearch + 1e-9; deg += 0.25) {
    const rad = (deg * Math.PI) / 180
    const cos = Math.cos(rad), sin = Math.sin(rad)
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity
    for (let i = 0; i < points.length; i += 2) {
      const x = points[i] * cos + points[i + 1] * sin
      const y = -points[i] * sin + points[i + 1] * cos
      if (x < minX) minX = x
      if (x > maxX) maxX = x
      if (y < minY) minY = y
      if (y > maxY) maxY = y
    }
    const a = (maxX - minX) * (maxY - minY)
    if (a < bestArea - 1e-6) { bestArea = a; best = deg }
  }
  return Math.abs(best) > o.tiltThreshold ? best : 0
}

// 8px の余白を付けた切り出し範囲（画像の外にはみ出さない）
export function paddedBox(box, imageWidth, imageHeight, padding = 8) {
  const x = Math.max(0, Math.floor(box.x - padding))
  const y = Math.max(0, Math.floor(box.y - padding))
  const x2 = Math.min(imageWidth, Math.ceil(box.x + box.w + padding))
  const y2 = Math.min(imageHeight, Math.ceil(box.y + box.h + padding))
  return { x, y, w: x2 - x, h: y2 - y }
}
