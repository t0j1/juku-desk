import { Controller } from "@hotwired/stimulus"

// 小テストの範囲（開始No. + 単語数）と問題数。入力中に検証し、終わりの番号を計算して見せる。
// 単語数はプルダウン。「自分で入力…」を選んだときだけ数値の欄を出す。
// エラーがある間（問題数が未選択の間も）は「テストをつくる」を押せなくする。
// 文言は app/models/quiz.rb と同じにしてある（サーバー側でも同じ検証をする）
export default class extends Controller {
  static targets = [ "start", "preset", "custom", "customWrap", "span", "count", "startError", "spanError", "countError",
                     "notice", "submit", "greeting", "rangeA", "rangeB", "rangeWords" ]
  static values = { numbers: Array, min: Number, max: Number, minCount: Number, maxCount: Number, defaultSpan: Number }

  connect() {
    if (this.presetTarget.value !== "custom") this.lastPreset = Number(this.presetTarget.value)
    this.validate()
  }

  // プルダウン：「自分で入力…」のときだけ数値の欄を出してフォーカスを移す。プリセットに戻したら隠す
  presetChanged() {
    const custom = this.presetTarget.value === "custom"
    this.customWrapTarget.hidden = !custom
    if (custom) {
      if (this.customTarget.value === "") this.customTarget.value = this.lastPreset ?? this.defaultSpanValue
      this.customTarget.focus()
    } else {
      this.lastPreset = Number(this.presetTarget.value)
    }
    this.validate()
  }

  fromCount() {
    this.validate()
  }

  validate() {
    const start = this.toInt(this.startTarget.value)
    const custom = this.presetTarget.value === "custom"
    const span = custom ? this.toInt(this.customTarget.value) : Number(this.presetTarget.value)
    const errors = { start: "", span: "", count: "" }

    if (start === null || start < this.minValue || start > this.maxValue) {
      errors.start = `${this.minValue}〜${this.maxValue}の数字を入れてください`
    }
    if (span === null || span < 1) {
      errors.span = "1以上の数字を入れてください"
    }
    const rangeOk = !errors.start && !errors.span

    // 終わりの番号 = 開始 + 語数 − 1。単語帳の最後を超えるときは最後で止める（エラーにはしない）
    const rawEnd = rangeOk ? start + span - 1 : null
    const end = rangeOk ? Math.min(rawEnd, this.maxValue) : null
    const available = rangeOk ? this.numbersValue.filter((n) => n >= start && n <= end).length : 0
    const count = this.selectedCount()
    // 未選択（count === null）はエラー文を出さず、吹き出しが問いかける。ボタンだけ押せなくする
    if (count !== null && (count < this.minCountValue || count > this.maxCountValue)) {
      errors.count = `問題数は ${this.minCountValue}〜${this.maxCountValue} で指定してください`
    } else if (count !== null && rangeOk && count > available) {
      errors.count = `範囲内の語数（${available}語）を超えています`
    }

    this.show(this.startTarget, this.startErrorTarget, errors.start)
    this.show(custom ? this.customTarget : this.presetTarget, this.spanErrorTarget, errors.span)
    this.showMessage(this.countErrorTarget, errors.count)

    const clamped = rangeOk && rawEnd > this.maxValue
    this.noticeTarget.hidden = !clamped
    this.noticeTarget.textContent = clamped ? `! 最後の番号までにしました（${available}語）` : ""

    const anyError = Object.values(errors).some(Boolean)
    this.submitTarget.disabled = anyError || count === null
    this.spanTarget.value = errors.span ? "" : span
    this.rangeATarget.textContent = errors.start ? "–" : start
    this.rangeBTarget.textContent = rangeOk ? end : "–"
    this.rangeWordsTarget.textContent = rangeOk ? available : "–"
    this.countTargets.forEach((radio) => radio.setAttribute("aria-checked", radio.checked ? "true" : "false"))
    this.greetingTarget.textContent = count === null ? "今日は何問いってみる？"
      : (!anyError ? "準備OK、印刷しよう" : `${count}問！いいね`)
  }

  selectedCount() {
    const checked = this.countTargets.find((radio) => radio.checked)
    return checked ? this.toInt(checked.value) : null
  }

  show(input, errorElement, message) {
    this.showMessage(errorElement, message)
    input.setAttribute("aria-invalid", message ? "true" : "false")
    input.classList.toggle("border-ng", Boolean(message))
    input.classList.toggle("border-quiz-line", !message)
  }

  showMessage(errorElement, message) {
    errorElement.hidden = !message
    errorElement.textContent = message ? `✕ ${message}` : ""
  }

  // 押したら紙吹雪を 0.8 秒。外部ライブラリなし。動きを減らす設定のときは出さずにそのまま送信する
  celebrate(event) {
    if (this.celebrating || this.submitTarget.disabled) return
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return

    event.preventDefault()
    this.celebrating = true
    const rect = this.submitTarget.getBoundingClientRect()
    const layer = document.createElement("div")
    layer.className = "confetti"
    layer.setAttribute("aria-hidden", "true")
    layer.style.top = `${rect.top + rect.height / 2}px`
    layer.style.left = `${rect.left + rect.width / 2}px`
    layer.style.width = "0"
    const colors = [ "#5B4BE0", "#F2A93B", "#F6B4C4", "#2A4E9A", "#7C5CF0", "#DCE6FA" ]
    for (let i = 0; i < 28; i++) {
      const piece = document.createElement("i")
      const angle = (Math.PI * 2 * i) / 28 + Math.random() * 0.4
      const distance = 90 + Math.random() * 130
      piece.style.background = colors[i % colors.length]
      piece.style.setProperty("--dx", `${Math.cos(angle) * distance}px`)
      piece.style.setProperty("--dy", `${Math.sin(angle) * distance - 40 + 80}px`)
      piece.style.setProperty("--rot", `${Math.round(Math.random() * 720 - 360)}deg`)
      layer.appendChild(piece)
    }
    document.body.appendChild(layer)
    setTimeout(() => {
      layer.remove()
      this.element.requestSubmit()
    }, 800)
  }

  toInt(value) {
    return /^\s*-?\d+\s*$/.test(value) ? parseInt(value, 10) : null
  }
}
