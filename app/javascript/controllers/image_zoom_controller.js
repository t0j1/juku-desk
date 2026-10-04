import { Controller } from "@hotwired/stimulus"

// 一覧の小さな切り出し画像をクリックすると、<dialog> で大きく表示する（背景のクリック・Esc・閉じるボタンで閉じる）
export default class extends Controller {
  static targets = [ "dialog", "image" ]

  open(event) {
    event.preventDefault()
    const src = event.currentTarget.dataset.imageZoomSrc
    this.imageTarget.src = src
    this.imageTarget.alt = event.currentTarget.querySelector("img")?.alt || ""
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  backdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
