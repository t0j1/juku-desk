"use strict";
// 閲覧ページ・管理ページ共通のヘルパー

const DOW = ["日", "月", "火", "水", "木", "金", "土"];
const SYMBOLS = { "高1授業": "①", "高2授業": "②", "高3授業": "③", "自習": "✎", "日曜自習室": "☀", "講習": "★", "休講": "✕", "休暇": "◆" };
const FALLBACK_COLOR = "#555a70";

const $ = id => document.getElementById(id);
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const pad = n => String(n).padStart(2, "0");
const ymd = (y, m, d) => `${y}-${pad(m + 1)}-${pad(d)}`;            // m は 0 始まり
const monthStart = (y, m) => ymd(y, m, 1);
const monthEnd = (y, m) => ymd(y, m, new Date(y, m + 1, 0).getDate());
const hhmm = t => (t ? String(t).slice(0, 5) : "");
const symOf = name => SYMBOLS[name] || "・";
const dowOf = k => DOW[new Date(k + "T00:00:00").getDay()];

// Supabase クライアント（設定が未入力なら null）
const db = (typeof supabase !== "undefined" && typeof SUPABASE_URL === "string" && !SUPABASE_URL.includes("YOUR-") && SUPABASE_ANON_KEY && !SUPABASE_ANON_KEY.includes("YOUR-"))
  ? supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY)
  : null;

// 種別チップ（色＋記号＋文字）。types: Map(name -> {color})
function chipHTML(e, types) {
  const color = types.get(e.type)?.color || FALLBACK_COLOR;
  return `<span class="chip" style="--c:${esc(color)}"><span class="sym" aria-hidden="true">${symOf(e.type)}</span><span class="vh">${esc(e.type)}：</span>${esc(e.title || e.type)}</span>`;
}

// ---- CSV ----
function parseCSV(text) {
  text = text.replace(/^﻿/, "");
  const rows = []; let row = [], cur = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"') { if (text[i + 1] === '"') { cur += '"'; i++; } else q = false; }
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === ",") { row.push(cur); cur = ""; }
    else if (c === "\n" || c === "\r") {
      if (c === "\r" && text[i + 1] === "\n") i++;
      row.push(cur); rows.push(row); row = []; cur = "";
    } else cur += c;
  }
  if (cur !== "" || row.length) { row.push(cur); rows.push(row); }
  return rows.filter(r => r.some(v => v.trim() !== ""));
}
const toCSV = rows => rows.map(r => r.map(v => `"${String(v ?? "").replace(/"/g, '""')}"`).join(",")).join("\r\n");

// 2026/9/1, 2026-09-01, 2026年9月1日 → YYYY-MM-DD（不正なら null）
function normDate(s) {
  const m = String(s).trim().match(/^(\d{4})\D+(\d{1,2})\D+(\d{1,2})/);
  if (!m) return null;
  const [y, mo, d] = [+m[1], +m[2], +m[3]];
  const dt = new Date(y, mo - 1, d);
  if (dt.getFullYear() !== y || dt.getMonth() !== mo - 1 || dt.getDate() !== d) return null;
  return `${y}-${pad(mo)}-${pad(d)}`;
}
// 9:00 / 09:00:00 / 9時30分 → HH:MM（空なら ""、不正なら null）
function normTime(s) {
  s = String(s ?? "").trim();
  if (!s) return "";
  const m = s.match(/^(\d{1,2})\s*[:時]\s*(\d{0,2})/);
  if (!m || +m[1] > 23 || +(m[2] || 0) > 59) return null;
  return `${pad(+m[1])}:${pad(+(m[2] || 0))}`;
}

// 開発用 DB につながっているときは、画面の隅に目印を出す（本番と取り違えないように）
if (typeof SUPABASE_ENV === "string" && SUPABASE_ENV === "dev") {
  const tag = document.createElement("div");
  tag.textContent = "開発DB";
  tag.style.cssText = "position:fixed;right:8px;bottom:8px;z-index:9999;padding:2px 8px;border-radius:6px;background:#c27a00;color:#fff;font:700 12px/1.6 sans-serif;pointer-events:none";
  document.body.appendChild(tag);
}
