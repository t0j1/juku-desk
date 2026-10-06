// print_settings_controller.js
// PR2: 印刷設定（解答欄の高さ・ページ内配置）のコントローラー

export default class extends Stimulus.Controller {
  static targets = ["answerHeight", "pageLayout", "questionsPerPage", "questionsPerPageContainer"]

  connect() {
    // 初期状態を適用
    this.applyAnswerHeight()
    this.applyPageLayout()
  }

  applyAnswerHeight() {
    const value = this.answerHeightTarget.value
    const sheet = document.querySelector(".mt-sheet")
    if (sheet) {
      switch (value) {
        case "narrow":
          sheet.style.setProperty("--mt-ruled-height", "var(--mt-answer-height-narrow)")
          break
        case "wide":
          sheet.style.setProperty("--mt-ruled-height", "var(--mt-answer-height-wide)")
          break
        default:
          sheet.style.setProperty("--mt-ruled-height", "var(--mt-answer-height-normal)")
      }
    }
  }

  applyPageLayout() {
    const value = this.pageLayoutTarget.value
    const sheet = document.querySelector(".mt-sheet")
    if (sheet) {
      sheet.dataset.pageLayout = value
      if (value === "count") {
        this.questionsPerPageContainerTarget.hidden = false
        this.applyQuestionsPerPage()
      } else {
        this.questionsPerPageContainerTarget.hidden = true
        sheet.style.removeProperty("--mt-questions-per-page")
      }
    }
  }

  applyQuestionsPerPage() {
    const value = this.questionsPerPageTarget.value
    const sheet = document.querySelector(".mt-sheet")
    if (sheet && this.pageLayoutTarget.value === "count") {
      sheet.style.setProperty("--mt-questions-per-page", value)
    }
  }
}