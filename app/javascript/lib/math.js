import renderMathInElement from "katex-auto-render"

// $...$（行の中）と $$...$$（独立した行）の LaTeX を KaTeX で描画する。
// 書き方が間違っていても throwOnError: false で、その部分は元のテキストのまま表示する。
export const MATH_OPTIONS = {
  delimiters: [
    { left: "$$", right: "$$", display: true },
    { left: "$", right: "$", display: false }
  ],
  throwOnError: false,
  errorColor: "inherit" // 解釈できない式は、赤字にせず元のテキストのまま見せる
}

export function renderMath(element) {
  renderMathInElement(element, MATH_OPTIONS)
}
