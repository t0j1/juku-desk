// driver_preset_controller.js
// プルダウンで「新しく追加する」を選んだときに入力欄を表示するコントローラー

export default class extends Stimulus.Controller {
  static targets = ["select", "input", "hidden"]
  static values = { allowBlank: Boolean }

  connect() {
    this.selectTarget.addEventListener("change", this.handleChange.bind(this))
    this.syncInitial()
  }

  syncInitial() {
    const value = this.selectTarget.value
    if (value === "__new__") {
      this.showInput()
    } else {
      this.hideInput()
      if (this.hiddenTarget) {
        this.hiddenTarget.value = value
      }
    }
  }

  handleChange() {
    const value = this.selectTarget.value
    if (value === "__new__") {
      this.showInput()
    } else {
      this.hideInput()
      if (this.hiddenTarget) {
        this.hiddenTarget.value = value
      }
    }
  }

  showInput() {
    this.inputTarget.hidden = false
    this.inputTarget.focus()
    this.selectTarget.hidden = true
    if (this.hiddenTarget) {
      this.hiddenTarget.value = ""
    }
  }

  hideInput() {
    this.inputTarget.hidden = true
    this.selectTarget.hidden = false
  }

  // 入力欄で保存（Enter またはフォーカスアウト）されたときの処理
  // 親フォームのサブミット前に呼ばれる想定
  finalize() {
    const newName = this.inputTarget.value.trim()
    if (newName) {
      // 新しいプリセット名を隠しフィールドにセット（サーバー側で追加される）
      if (this.hiddenTarget) {
        this.hiddenTarget.value = newName
      }
      // プルダウンにも反映（次回から選べるように）
      const option = document.createElement("option")
      option.value = newName
      option.textContent = newName
      this.selectTarget.insertBefore(option, this.selectTarget.querySelector('option[value="__new__"]'))
      this.selectTarget.value = newName
    }
    this.hideInput()
  }
}
