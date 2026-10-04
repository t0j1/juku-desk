import { Controller } from "@hotwired/stimulus"

// 小テストの範囲と問題数。スライダー・数字入力・問題数ボタンを同期し、入力中に検証する。
// エラーがある間（問題数が未選択の間も）は「テストをつくる」を押せなくする。
// 文言は app/models/quiz.rb と同じにしてある（サーバー側でも同じ検証をする）
export default class extends Controller {
  static targets = [ "start", "end", "count", "startError", "endError", "countError", "submit", "greeting",
                     "startSlider", "endSlider", "slider", "rangeA", "rangeB", "rangeWords" ]
  static values = { numbers: Array, min: Number, max: Number, minCount: Number, maxCount: Number }

  connect() {
    this.validate()
  }

  // スライダー → 数字入力。開始が終了を超えないよう、動かしている側を止める
  fromStartSlider() {
    const value = Math.min(Number(this.startSliderTarget.value), Number(this.endSliderTarget.value))
    this.startSliderTarget.value = value
    this.startTarget.value = value
    this.validate()
  }

  fromEndSlider() {
    const value = Math.max(Number(this.endSliderTarget.value), Number(this.startSliderTarget.value))
    this.endSliderTarget.value = value
    this.endTarget.value = value
    this.validate()
  }

  // 数字入力 → スライダー（数字として読めるときだけ）
  fromInputs() {
    this.validate()
  }

  fromCount() {
    this.validate()
  }

  validate() {
    const start = this.toInt(this.startTarget.value)
    const end = this.toInt(this.endTarget.value)
    const count = this.selectedCount()
    const errors = { start: "", end: "", count: "" }
    let rangeOk = true

    for (const [ key, value ] of [ [ "start", start ], [ "end", end ] ]) {
      if (value === null) {
        errors[key] = "数字で入力してください"
        rangeOk = false
      } else if (value < this.minValue || value > this.maxValue) {
        errors[key] = `${this.minValue}〜${this.maxValue} の範囲で入力してください`
        rangeOk = false
      }
    }
    if (rangeOk && start > end) {
      errors.start = "開始は終了以下にしてください"
      rangeOk = false
    }

    const available = rangeOk ? this.numbersValue.filter((n) => n >= start && n <= end).length : 0
    // 未選択（count === null）はエラー文を出さず、吹き出しが問いかける。ボタンだけ押せなくする
    if (count !== null && (count < this.minCountValue || count > this.maxCountValue)) {
      errors.count = `問題数は ${this.minCountValue}〜${this.maxCountValue} で指定してください`
    } else if (count !== null && rangeOk && count > available) {
      errors.count = `範囲内の語数（${available}語）を超えています`
    }

    this.show(this.startTarget, this.startErrorTarget, errors.start)
    this.show(this.endTarget, this.endErrorTarget, errors.end)
    this.showMessage(this.countErrorTarget, errors.count)

    const anyError = Object.values(errors).some(Boolean)
    this.submitTarget.disabled = anyError || count === null
    this.syncSliders(rangeOk ? start : null, rangeOk ? end : null)
    this.rangeATarget.textContent = start ?? "–"
    this.rangeBTarget.textContent = end ?? "–"
    this.rangeWordsTarget.textContent = rangeOk ? available : "–"
    this.countTargets.forEach((radio) => radio.setAttribute("aria-checked", radio.checked ? "true" : "false"))
    this.greetingTarget.textContent = count === null ? "今日は何問いってみる？"
      : (!anyError ? "準備OK、印刷しよう" : `${count}問！いいね`)
  }

  // 範囲と問題数の両方が正しいときだけ「準備OK」。問題数だけ選んだ段階は「{n}問！いいね」
  syncSliders(start, end) {
    if (start === null || end === null) return
    this.startSliderTarget.value = start
    this.endSliderTarget.value = end
    const span = Math.max(this.maxValue - this.minValue, 1)
    this.sliderTarget.style.setProperty("--lo", (start - this.minValue) / span)
    this.sliderTarget.style.setProperty("--hi", (end - this.minValue) / span)
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
