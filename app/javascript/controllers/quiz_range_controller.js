import { Controller } from "@hotwired/stimulus"

// 小テストの範囲と問題数。入力中に検証し、エラーがある間は「問題を作成」を押せなくする。
// 文言は app/models/quiz.rb と同じにしてある（サーバー側でも同じ検証をする）
export default class extends Controller {
  static targets = [ "start", "end", "count", "startError", "endError", "countError", "submit", "split", "preset" ]
  static values = { numbers: Array, min: Number, max: Number, minCount: Number, maxCount: Number }

  connect() {
    this.validate()
  }

  decrement() {
    this.step(-1)
  }

  increment() {
    this.step(1)
  }

  preset(event) {
    this.countTarget.value = event.currentTarget.dataset.count
    this.validate()
  }

  step(delta) {
    const current = this.toInt(this.countTarget.value) ?? this.minCountValue
    this.countTarget.value = Math.min(this.maxCountValue, Math.max(this.minCountValue, current + delta))
    this.validate()
  }

  validate() {
    const start = this.toInt(this.startTarget.value)
    const end = this.toInt(this.endTarget.value)
    const count = this.toInt(this.countTarget.value)
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
    if (count === null || count < this.minCountValue || count > this.maxCountValue) {
      errors.count = `問題数は ${this.minCountValue}〜${this.maxCountValue} で指定してください`
    } else if (rangeOk && count > available) {
      errors.count = `範囲内の語数（${available}語）を超えています`
    }

    this.show(this.startTarget, this.startErrorTarget, errors.start)
    this.show(this.endTarget, this.endErrorTarget, errors.end)
    this.show(this.countTarget, this.countErrorTarget, errors.count)
    this.submitTarget.disabled = Object.values(errors).some(Boolean)

    const total = count === null ? 0 : count
    const left = Math.ceil(total / 2)
    this.splitTarget.textContent = `左 ${left}／右 ${total - left}`
    this.presetTargets.forEach((button) => this.markPreset(button, Number(button.dataset.count) === count))
  }

  show(input, errorElement, message) {
    errorElement.hidden = !message
    errorElement.textContent = message ? `✕ ${message}` : ""
    input.setAttribute("aria-invalid", message ? "true" : "false")
    input.classList.toggle("border-ng", Boolean(message))
    input.classList.toggle("border-line-strong", !message)
  }

  // 選択中のプリセットは塗り＋✓（色だけで区別しない）
  markPreset(button, selected) {
    button.classList.toggle("bg-primary", selected)
    button.classList.toggle("text-white", selected)
    button.classList.toggle("border-primary", selected)
    button.classList.toggle("bg-white", !selected)
    button.classList.toggle("text-ink", !selected)
    button.classList.toggle("border-line-strong", !selected)
    button.textContent = `${selected ? "✓ " : ""}${button.dataset.count}`
    button.setAttribute("aria-pressed", selected ? "true" : "false")
  }

  toInt(value) {
    return /^\s*-?\d+\s*$/.test(value) ? parseInt(value, 10) : null
  }
}
