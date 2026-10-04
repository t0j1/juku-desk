import { Controller } from "@hotwired/stimulus"

// 768px 未満でサイドバーを開閉する（768px 以上では常に表示なので、何もしない）
export default class extends Controller {
  static targets = [ "panel", "scrim", "button" ]

  connect() {
    this.onKeydown = (e) => { if (e.key === "Escape") this.close() }
    this.onResize = () => { if (window.matchMedia("(min-width: 768px)").matches) this.close() }
    document.addEventListener("keydown", this.onKeydown)
    window.addEventListener("resize", this.onResize)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("resize", this.onResize)
  }

  toggle() {
    this.#set(this.panelTarget.dataset.open !== "true")
  }

  close() {
    this.#set(false)
  }

  #set(open) {
    this.panelTarget.dataset.open = String(open)
    this.scrimTarget.classList.toggle("hidden", !open)
    this.buttonTarget.setAttribute("aria-expanded", String(open))
    this.buttonTarget.setAttribute("aria-label", open ? "メニューを閉じる" : "メニューを開く")
  }
}
