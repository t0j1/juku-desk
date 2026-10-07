import test from "node:test"
import assert from "node:assert/strict"
import { detectMarkings, paddedBox } from "../../app/javascript/lib/marking_detector.js"

// 教材画像に見立てた合成画像（白い紙に、黒い文字っぽい線と赤い図形）
function paper(width, height) {
  const data = new Uint8ClampedArray(width * height * 4).fill(255)
  const image = { data, width, height }
  // 黒い文字っぽい横線
  for (let y = 40; y < height; y += 60) rect(image, 30, y, width - 60, 3, [30, 30, 30], true)
  return image
}

function setPixel(image, x, y, rgb) {
  if (x < 0 || y < 0 || x >= image.width || y >= image.height) return
  const i = (y * image.width + x) * 4
  image.data[i] = rgb[0]; image.data[i + 1] = rgb[1]; image.data[i + 2] = rgb[2]; image.data[i + 3] = 255
}

function rect(image, x, y, w, h, rgb, fill = false, thickness = 4) {
  for (let yy = y; yy < y + h; yy++) {
    for (let xx = x; xx < x + w; xx++) {
      const edge = xx < x + thickness || xx >= x + w - thickness || yy < y + thickness || yy >= y + h - thickness
      if (fill || edge) setPixel(image, xx, yy, rgb)
    }
  }
}

// 中心まわりに deg 度傾けた枠線
function tiltedFrame(image, cx, cy, w, h, deg, rgb, thickness = 4) {
  const rad = (deg * Math.PI) / 180
  const cos = Math.cos(rad), sin = Math.sin(rad)
  const r = Math.ceil(Math.hypot(w, h) / 2) + 2
  for (let y = -r; y <= r; y++) {
    for (let x = -r; x <= r; x++) {
      const u = x * cos + y * sin, v = -x * sin + y * cos
      if (Math.abs(u) > w / 2 || Math.abs(v) > h / 2) continue
      if (Math.abs(u) > w / 2 - thickness || Math.abs(v) > h / 2 - thickness) setPixel(image, Math.round(cx + x), Math.round(cy + y), rgb)
    }
  }
}

const RED = [220, 30, 30]
const near = (actual, expected, tol = 10) => Math.abs(actual - expected) <= tol

function assertBox(found, x, y, w, h) {
  assert.ok(near(found.x, x) && near(found.y, y) && near(found.w, w) && near(found.h, h),
    `期待 ${[x, y, w, h]} / 実際 ${[found.x, found.y, found.w, found.h]}`)
}

test("赤枠が1つなら1件、座標は各辺10px以内", () => {
  const img = paper(800, 600)
  rect(img, 100, 120, 300, 200, RED)
  const found = detectMarkings(img)
  assert.equal(found.length, 1)
  assertBox(found[0], 100, 120, 300, 200)
  assert.ok(found[0].confidence > 0.9)
  assert.equal(found[0].angle, 0)
})

test("赤枠が3つなら3件", () => {
  const img = paper(800, 600)
  rect(img, 40, 50, 260, 150, RED)
  rect(img, 400, 60, 300, 180, RED)
  rect(img, 150, 350, 450, 200, RED)
  const found = detectMarkings(img)
  assert.equal(found.length, 3)
  const has = (x, y, w, h) => found.some((f) => near(f.x, x) && near(f.y, y) && near(f.w, w) && near(f.h, h))
  assert.ok(has(40, 50, 260, 150) && has(400, 60, 300, 180) && has(150, 350, 450, 200), JSON.stringify(found))
})

test("赤がなければ0件", () => {
  assert.equal(detectMarkings(paper(800, 600)).length, 0)
})

test("塗りつぶした赤い図形は検出しない", () => {
  const img = paper(800, 600)
  rect(img, 100, 100, 250, 200, RED, true)
  assert.equal(detectMarkings(img).length, 0)
})

test("画像全体を囲む赤い外枠は検出しない（中の枠は検出する）", () => {
  const img = paper(800, 600)
  rect(img, 0, 0, 800, 600, RED, false, 6)
  assert.equal(detectMarkings(img).length, 0)
  rect(img, 200, 150, 300, 200, RED)
  const found = detectMarkings(img)
  assert.equal(found.length, 1)
  assertBox(found[0], 200, 150, 300, 200)
})

test("入れ子の枠は外側にまとめる", () => {
  const img = paper(800, 600)
  rect(img, 100, 100, 400, 300, RED)
  rect(img, 150, 150, 150, 100, RED)
  const found = detectMarkings(img)
  assert.equal(found.length, 1)
  assertBox(found[0], 100, 100, 400, 300)
})

test("細長すぎる赤い線は検出しない", () => {
  const img = paper(800, 600)
  rect(img, 50, 300, 700, 12, RED, true)
  assert.equal(detectMarkings(img).length, 0)
})

test("小さすぎる赤い印（面積0.5%未満）は検出しない", () => {
  const img = paper(800, 600)
  rect(img, 100, 100, 40, 40, RED)
  assert.equal(detectMarkings(img).length, 0)
})

test("傾いた枠は傾きを返す（±0.5°超のとき）", () => {
  const img = paper(800, 600)
  tiltedFrame(img, 400, 300, 360, 220, 2, RED)
  const found = detectMarkings(img)
  assert.equal(found.length, 1)
  assert.ok(Math.abs(Math.abs(found[0].angle) - 2) <= 0.5, `angle=${found[0].angle}`)
})

test("しきい値は options で変えられる（最小面積を上げると小さい枠が消える）", () => {
  const img = paper(800, 600)
  rect(img, 100, 100, 120, 100, RED)
  assert.equal(detectMarkings(img).length, 1)
  assert.equal(detectMarkings(img, { minAreaRatio: 0.2 }).length, 0)
})

test("paddedBox は8pxの余白を付け、画像の外にははみ出さない", () => {
  assert.deepEqual(paddedBox({ x: 100, y: 100, w: 50, h: 40 }, 800, 600), { x: 92, y: 92, w: 66, h: 56 })
  assert.deepEqual(paddedBox({ x: 2, y: 3, w: 50, h: 40 }, 800, 600), { x: 0, y: 0, w: 60, h: 51 })
})

// 白抜き文字入りの赤い見出しタブ（塗りブロックに、白い小さな四角で文字を表す）
function tab(image, x, y, w, h) {
  rect(image, x, y, w, h, [220, 30, 30], true)
  for (let ty = y + 20; ty < y + h - 20; ty += 24) rect(image, x + 8, ty, w - 16, 10, [255, 255, 255], true)
}

test("ページ右端の、文字入りの赤い見出しタブだけの画像は0件（誤検出しない）", () => {
  const image = paper(800, 600)
  tab(image, 760, 120, 40, 260)
  assert.equal(detectMarkings(image).length, 0)
})

test("枠と端の見出しタブがあるときは、枠だけ検出する", () => {
  const image = paper(800, 600)
  rect(image, 80, 100, 400, 200, [220, 30, 30])
  tab(image, 760, 120, 40, 260)
  const found = detectMarkings(image)
  assert.equal(found.length, 1)
  assert.ok(Math.abs(found[0].x - 80) <= 10 && Math.abs(found[0].w - 400) <= 20)
})

test("端に接していなくても、中が詰まった文字入りの塗りブロックは枠ではない", () => {
  const image = paper(800, 600)
  tab(image, 300, 200, 160, 120)
  assert.equal(detectMarkings(image).length, 0)
})

test("端の判定・中の詰まり具合のしきい値は options で変えられる", () => {
  const image = paper(800, 600)
  tab(image, 760, 120, 40, 260)
  assert.ok(detectMarkings(image, { maxInnerFillRatio: 1, tabAspectRatio: 100 }).length >= 1)
})
