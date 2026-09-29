"use strict";
// 予約の申請に成功したときの演出：画面の下から猫が出てきて手を振り、肉球が舞ってから引っ込む（約3秒）。
// 操作の邪魔をしないよう、クリックは下の画面にそのまま通す。視差効果を減らす設定の人には、動かさずに小さな猫だけ出す。

const CAT_SVG = `
<svg class="cat-svg" viewBox="0 0 200 190" aria-hidden="true">
  <!-- しっぽ -->
  <path class="cat-tail" d="M150 165 C185 160 190 120 172 105" fill="none" stroke="#e8914a" stroke-width="14" stroke-linecap="round"/>
  <!-- からだ -->
  <ellipse cx="100" cy="165" rx="58" ry="42" fill="#f2a65a"/>
  <ellipse cx="100" cy="172" rx="32" ry="26" fill="#fff3e2"/>
  <!-- 耳 -->
  <path d="M52 62 L60 18 L88 48 Z" fill="#f2a65a"/><path d="M60 54 L64 30 L80 48 Z" fill="#f7b8c4"/>
  <path d="M148 62 L140 18 L112 48 Z" fill="#f2a65a"/><path d="M140 54 L136 30 L120 48 Z" fill="#f7b8c4"/>
  <!-- 頭 -->
  <ellipse cx="100" cy="88" rx="56" ry="48" fill="#f2a65a"/>
  <path d="M100 42 v14 M86 45 l3 12 M114 45 l-3 12" stroke="#d9783a" stroke-width="5" stroke-linecap="round"/>
  <!-- 目（にっこり） -->
  <path d="M68 86 q10 -10 20 0" fill="none" stroke="#3b2a1e" stroke-width="5" stroke-linecap="round"/>
  <path d="M112 86 q10 -10 20 0" fill="none" stroke="#3b2a1e" stroke-width="5" stroke-linecap="round"/>
  <!-- ほっぺ -->
  <ellipse cx="66" cy="102" rx="9" ry="6" fill="#f7a1b0" opacity=".8"/>
  <ellipse cx="134" cy="102" rx="9" ry="6" fill="#f7a1b0" opacity=".8"/>
  <!-- 鼻と口 -->
  <path d="M95 98 h10 l-5 6 z" fill="#e0707f"/>
  <path d="M100 104 q-6 8 -12 4 M100 104 q6 8 12 4" fill="none" stroke="#3b2a1e" stroke-width="3" stroke-linecap="round"/>
  <!-- ひげ -->
  <path d="M40 96 l24 3 M40 108 l24 -2 M160 96 l-24 3 M160 108 l-24 -2" stroke="#3b2a1e" stroke-width="2.5" stroke-linecap="round"/>
  <!-- 左手（おいている） -->
  <ellipse cx="72" cy="150" rx="14" ry="11" fill="#f7b46e"/>
  <!-- 右手（ふっている） -->
  <g class="cat-paw">
    <path d="M140 140 C150 128 154 112 150 100" fill="none" stroke="#f2a65a" stroke-width="20" stroke-linecap="round"/>
    <circle cx="150" cy="96" r="13" fill="#f7b46e"/>
    <circle cx="145" cy="92" r="3" fill="#f7a1b0"/><circle cx="152" cy="89" r="3" fill="#f7a1b0"/><circle cx="157" cy="94" r="3" fill="#f7a1b0"/>
  </g>
</svg>`;

const PAW_SVG = `<svg viewBox="0 0 40 40" aria-hidden="true"><ellipse cx="20" cy="26" rx="10" ry="8"/><circle cx="9" cy="15" r="4.5"/><circle cx="17" cy="9" r="4.5"/><circle cx="27" cy="10" r="4.5"/><circle cx="33" cy="17" r="4.5"/></svg>`;

function celebrateCat() {
  const reduce = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches;
  if (reduce) {
    // 動かさずに、完了メッセージの横に小さな猫だけ
    const msg = document.querySelector("#done .done-msg");
    if (msg && !msg.querySelector(".done-cat")) msg.insertAdjacentHTML("afterbegin", `<span class="done-cat">${CAT_SVG}</span>`);
    return;
  }
  document.querySelector(".cat-stage")?.remove();
  const stage = document.createElement("div");
  stage.className = "cat-stage";
  stage.setAttribute("aria-hidden", "true");
  const paws = Array.from({ length: 7 }, (_, i) => {
    const left = 8 + i * 13 + Math.random() * 6, delay = 0.5 + Math.random() * 0.9, size = 22 + Math.random() * 14;
    return `<span class="cat-pawprint" style="left:${left}%;--d:${delay.toFixed(2)}s;--s:${size.toFixed(0)}px;--r:${(Math.random() * 60 - 30).toFixed(0)}deg">${PAW_SVG}</span>`;
  }).join("");
  stage.innerHTML = `${paws}<div class="cat-pop"><div class="cat-bubble">にゃ！予約できたよ</div>${CAT_SVG}</div>`;
  document.body.appendChild(stage);
  setTimeout(() => stage.remove(), 3400);
}
