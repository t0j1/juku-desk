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
