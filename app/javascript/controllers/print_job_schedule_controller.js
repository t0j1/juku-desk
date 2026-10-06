// print_job_schedule_controller.js
// 印刷日時・期限のバリデーション（期限が開始より前ならエラー）

export default class extends Stimulus.Controller {
  static targets = ["scheduledAt", "expiresAt", "error"]

  connect() {
    // 初期状態で検証
    this.validate()
  }

  validate() {
    const scheduled = this.scheduledAtTarget?.value
    const expires = this.expiresAtTarget?.value

    if (scheduled && expires) {
      const scheduledTime = new Date(scheduled).getTime()
      const expiresTime = new Date(expires).getTime()

      if (expiresTime <= scheduledTime) {
        this.showError("期限は印刷日時より後にしてください")
        return false
      }
    }
    this.hideError()
    return true
  }

  validateForm(event) {
    if (!this.validate()) {
      event.preventDefault()
    }
  }

  showError(message) {
    if (this.errorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.hidden = false
    }
    if (this.expiresAtTarget) {
      this.expiresAtTarget.setAttribute("aria-invalid", "true")
    }
  }

  hideError() {
    if (this.errorTarget) {
      this.errorTarget.textContent = ""
      this.errorTarget.hidden = true
    }
    if (this.expiresAtTarget) {
      this.expiresAtTarget.removeAttribute("aria-invalid")
    }
  }
}