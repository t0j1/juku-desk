import { Controller } from "@hotwired/stimulus"

// Turbo のページ遷移・フォーム送信が遅いときの読み込み表示。
// 0.4 秒未満は何も出さない／3 秒で理由／15 秒で「推定」の斜線／45 秒で再読み込み。％は出さない（分母がない）ので、バーは「動いている」ことだけを示す。
// 進み具合は単調に増え、99% を超えない（逆行・停止しない）。rAF は 1 本で、1 フレームに DOM を書くのは 1 回。
export default class extends Controller {
  static targets = [ "fill", "seconds", "reason", "slow", "estimate" ]
  // しきい値（ミリ秒）。画面の既定は 0.4 秒・3 秒・15 秒・45 秒。テストで短くできるよう、data 属性で上書きできる
  static values = { showMs: { type: Number, default: 400 }, reasonMs: { type: Number, default: 3000 }, estimateMs: { type: Number, default: 15000 }, slowMs: { type: Number, default: 45000 } }

  connect() {
    this.startedAt = null
    this.frame = null
    this.last = {}
    this.reduced = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
    this.begin = () => this.start()
    this.finish = () => this.stop()
    this.submitEnd = (event) => {
      // 成功したフォーム送信は、このあとリダイレクトの遷移が続く。画面が差し替わらない応答（Turbo Stream）だけここで終える
      const type = event.detail?.fetchResponse?.response?.headers?.get("content-type") || ""
      if (!event.detail?.success || type.includes("turbo-stream")) this.stop()
    }
    this.listeners = [
      [ "turbo:visit", this.begin ], [ "turbo:submit-start", this.begin ],
      [ "turbo:load", this.finish ], [ "turbo:render", this.finish ], [ "turbo:fetch-request-error", this.finish ],
      [ "turbo:submit-end", this.submitEnd ], [ "pageshow", this.finish ]
    ]
    this.listeners.forEach(([ name, fn ]) => document.addEventListener(name, fn))
  }

  disconnect() {
    this.listeners.forEach(([ name, fn ]) => document.removeEventListener(name, fn))
    this.stop()
  }

  start() {
    if (this.startedAt !== null) return
    this.startedAt = performance.now()
    this.frame = requestAnimationFrame((t) => this.tick(t))
  }

  stop() {
    if (this.startedAt === null) return
    cancelAnimationFrame(this.frame)
    this.startedAt = null
    this.frame = null
    if (this.last.shown) this.write({ shown: false, state: "idle", seconds: 0, progress: 0 })
    this.last = {}
  }

  reload() { window.location.reload() }

  tick(now) {
    if (this.startedAt === null) return
    const elapsed = now - this.startedAt
    if (elapsed >= this.showMsValue) {
      const state = elapsed >= this.slowMsValue ? "slow" : elapsed >= this.estimateMsValue ? "estimate" : elapsed >= this.reasonMsValue ? "reason" : "loading"
      // 0 → 99% へなめらかに近づく。時間に対して単調増加で、上限は 99%
      const progress = Math.min(0.99, 0.99 * (1 - Math.exp(-elapsed / 12000)))
      this.write({ shown: true, state, seconds: Math.floor(elapsed / 1000), progress })
    }
    this.frame = requestAnimationFrame((t) => this.tick(t))
  }

  // 変わった値だけを、1 フレームにまとめて書く
  write(next) {
    const prev = this.last
    this.last = next
    if (prev.shown !== next.shown) {
      this.element.hidden = !next.shown
      this.element.setAttribute("aria-busy", next.shown ? "true" : "false")
    }
    if (prev.state !== next.state) {
      this.element.dataset.state = next.state
      this.reasonTarget.hidden = !(next.state === "reason" || next.state === "estimate" || next.state === "slow")
      this.slowTarget.hidden = next.state !== "slow"
      this.estimateTarget.hidden = !(next.state === "estimate" || next.state === "slow")
    }
    if (prev.seconds !== next.seconds) this.secondsTarget.textContent = next.seconds
    if (!this.reduced) {
      this.fillTarget.style.transform = `scaleX(${next.progress})`
      if (next.shown) this.element.dataset.progress = next.progress.toFixed(4)
      else delete this.element.dataset.progress
    }
  }
}
