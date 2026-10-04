"use strict";
// 閲覧ページ（誰でも閲覧可・公開済みの予定のみ）

const now = new Date();
const todayKey = ymd(now.getFullYear(), now.getMonth(), now.getDate());
let view = { y: now.getFullYear(), m: now.getMonth() };
let types = null;              // Map(name -> {color, sort_order})
let byDate = new Map();
const cache = new Map();       // "y-m" -> Map(date -> events[])
let token = 0;                 // 連打で古い応答が上書きしないように

function setStatus(html, isError) {
  const s = $("status");
  s.hidden = !html; s.innerHTML = html || ""; s.classList.toggle("error", !!isError);
}

async function ensureTypes() {
  if (types) return;
  const { data, error } = await db.from("event_types").select("name,color,sort_order").order("sort_order");
  if (error) throw error;
  types = new Map(data.map(t => [t.name, t]));
  $("legend").innerHTML = data.map(t =>
    `<li><span class="chip" style="--c:${esc(t.color)}"><span class="sym" aria-hidden="true">${symOf(t.name)}</span>${esc(t.name)}</span></li>`).join("");
}

async function loadMonth(y, m) {
  const k = `${y}-${m}`;
  if (cache.has(k)) return cache.get(k);
  const { data, error } = await db.from("events")
    .select("id,event_date,type,title,start_time,end_time,note")
    .eq("is_published", true)                       // 管理者ログイン中でも下書きは出さない
    .gte("event_date", monthStart(y, m)).lte("event_date", monthEnd(y, m))
    .order("start_time", { ascending: true, nullsFirst: true });
  if (error) throw error;
  const map = new Map();
  data.forEach(e => { if (!map.has(e.event_date)) map.set(e.event_date, []); map.get(e.event_date).push(e); });
  cache.set(k, map);
  return map;
}

async function show() {
  const my = ++token;
  $("title").textContent = `${view.y}年 ${view.m + 1}月`;
  $("grid").innerHTML = ""; $("list").innerHTML = "";
  if (!db) { setStatus("接続設定（js/config.js）が未入力です。", true); return; }
  setStatus("読み込み中…");
  try {
    await ensureTypes();
    const map = await loadMonth(view.y, view.m);
    if (my !== token) return;
    byDate = map; setStatus(""); render();
  } catch (err) {
    if (my !== token) return;
    console.error(err);
    setStatus(`予定を読み込めませんでした。<br><small>${esc(err.message || err)}</small><br><button class="btn small" id="retry" type="button">再読み込み</button>`, true);
    $("retry").onclick = show;
  }
}

function render() {
  const { y, m } = view;
  const first = new Date(y, m, 1).getDay(), days = new Date(y, m + 1, 0).getDate();
  let g = DOW.map((d, i) => `<div class="dow ${i === 0 ? "sun" : i === 6 ? "sat" : ""}">${d}</div>`).join("");
  for (let i = 0; i < first; i++) g += `<div class="cell blank"></div>`;
  let l = "";
  for (let d = 1; d <= days; d++) {
    const k = ymd(y, m, d), w = (first + d - 1) % 7, evs = byDate.get(k) || [];
    const isToday = k === todayKey;
    const cls = `${w === 0 ? "sun" : w === 6 ? "sat" : ""} ${isToday ? "today" : ""}`;
    const badge = isToday ? `<span class="today-badge">今日</span>` : "";
    const label = `${m + 1}月${d}日 ${DOW[w]}曜日${isToday ? " 今日" : ""} 予定${evs.length}件`;
    g += `<button type="button" class="cell ${cls}" data-k="${k}" aria-label="${label}"><span class="num">${d}${badge}</span>${evs.slice(0, 3).map(e => chipHTML(e, types)).join("")}${evs.length > 3 ? `<span class="more">他${evs.length - 3}件</span>` : ""}</button>`;
    l += `<li><button type="button" class="row ${cls}" data-k="${k}" aria-label="${label}"><div class="rd">${d}日（${DOW[w]}）${badge}</div>${evs.length ? evs.map(e => chipHTML(e, types)).join("") : `<span class="empty">予定なし</span>`}</button></li>`;
  }
  $("grid").innerHTML = g;
  $("list").innerHTML = l;
}

function openDetail(k) {
  const [y, m, d] = k.split("-").map(Number);
  const evs = byDate.get(k) || [];
  $("dlg-title").textContent = `${y}年${m}月${d}日（${dowOf(k)}）`;
  $("dlg-body").innerHTML = evs.length ? evs.map(e => {
    const color = types.get(e.type)?.color || FALLBACK_COLOR;
    const time = e.start_time ? `${hhmm(e.start_time)}${e.end_time ? " – " + hhmm(e.end_time) : " 〜"}` : "";
    return `<div class="item" style="--c:${esc(color)}">
      <div class="kind"><span class="sym" aria-hidden="true">${symOf(e.type)}</span> ${esc(e.type)}</div>
      <div class="title">${esc(e.title)}</div>
      ${time ? `<div class="time">🕒 ${time}</div>` : ""}
      ${e.note ? `<div class="note">📝 ${esc(e.note)}</div>` : ""}</div>`;
  }).join("") : `<p class="status">この日の予定はありません。</p>`;
  $("dlg").showModal();
}

function move(delta) {
  const d = new Date(view.y, view.m + delta, 1);
  view = { y: d.getFullYear(), m: d.getMonth() };
  show();
}

$("prev").onclick = () => move(-1);
$("next").onclick = () => move(1);
$("today").onclick = () => { view = { y: now.getFullYear(), m: now.getMonth() }; show(); };
$("dlg-close").onclick = () => $("dlg").close();
$("dlg").addEventListener("click", e => { if (e.target === $("dlg")) $("dlg").close(); });
document.addEventListener("click", e => {
  const b = e.target.closest("[data-k]");
  if (b) openDetail(b.dataset.k);
});

show();
