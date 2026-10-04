"use strict";
// 送迎予約の共通部分（生徒用ページ・管理画面で共用）。common.js のあとに読み込む。

const PICKUP_STATUS = { pending: "未承認", proposing: "調整中", approved: "承認", rejected: "却下", cancelled: "キャンセル" };

// 画面に出す状態。未承認でも、相乗りの打診中（便に入っている／回答待ちの打診がある）なら「調整中」
const pickupStatusOf = r => (r.status === "pending" && (r.group_id || r.proposal_id) ? "proposing" : r.status);
const pickupBadge = key => `<span class="pst pst-${key}">${PICKUP_STATUS[key] || esc(key)}</span>`;

// "17:05" ⇔ 1025（分）
const toMin = t => { const [h, m] = String(t).split(":").map(Number); return h * 60 + m; };
const fromMin = m => `${pad(Math.floor(m / 60))}:${pad(m % 60)}`;

// "2026-10-01" → "10/1（木）"
const fmtDay = k => { const [, m, d] = String(k).split("-"); return `${+m}/${+d}（${dowOf(k)}）`; };

// 相乗りの共通時刻の提案。
//   times     : 各予約の希望時刻 ["17:00", "17:15"]
//   tolerance : 希望から許容するずれ（分）
//   step      : 候補の刻み（分）
//   window    : 出発できる範囲 ["16:00", "20:45"]（無ければ制限なし）
//   busy      : ほかの便の走行時間 [["18:00", "18:15"], ...]（重なる候補は除く）
//   trip      : この便の所要時間（分）
// 範囲 ＝ [一番遅い希望 − 許容, 一番早い希望 ＋ 許容] ∩ window。候補は step 刻み。
// おすすめは、希望の最小と最大のまん中に一番近い候補（同じ近さなら遅いほう）。
// 例：17:00 と 17:15・許容10分 → 範囲 17:05〜17:10、おすすめ 17:10
function suggestTime(times, { tolerance = 10, step = 5, window = null, busy = [], trip = 15 } = {}) {
  const ts = times.map(toMin);
  if (!ts.length) return { from: null, to: null, candidates: [], best: null };
  let lo = Math.max(...ts) - tolerance, hi = Math.min(...ts) + tolerance;
  if (window) { lo = Math.max(lo, toMin(window[0])); hi = Math.min(hi, toMin(window[1])); }
  const first = Math.ceil(lo / step) * step;
  const busyMin = busy.map(([s, e]) => [toMin(s), toMin(e)]);
  const candidates = [];
  for (let c = first; c <= hi; c += step) {
    if (!busyMin.some(([s, e]) => c < e && s < c + trip)) candidates.push(c);
  }
  const mid = (Math.min(...ts) + Math.max(...ts)) / 2;
  let best = null;
  for (const c of candidates) if (best === null || Math.abs(c - mid) <= Math.abs(best - mid)) best = c;
  return {
    from: lo <= hi ? fromMin(first <= hi ? first : lo) : null,
    to: lo <= hi ? fromMin(hi - (hi % step)) : null,
    candidates: candidates.map(fromMin),
    best: best === null ? null : fromMin(best),
  };
}
