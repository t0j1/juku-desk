"use strict";
// 管理画面。権限は画面ではなく DB の RLS（admins テーブル）で守られている。

let types = [];                 // [{name,color,sort_order}]
let typeMap = new Map();
let cur = { y: new Date().getFullYear(), m: new Date().getMonth() };
let editingId = null;
let toastTimer;

// ---------- 共通 ----------
function toast(msg, isErr) {
  const t = $("toast");
  t.textContent = msg; t.classList.toggle("err", !!isErr); t.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => { t.hidden = true; }, isErr ? 7000 : 3500);
}
async function guard(fn) {
  try { await fn(); } catch (e) { console.error(e); toast(e.message || String(e), true); }
}
const must = ({ data, error }) => { if (error) throw error; return data; };
const fmtDate = k => { const [, m, d] = k.split("-"); return `${+m}/${+d}（${dowOf(k)}）`; };
const timeText = e => e.start_time ? `${hhmm(e.start_time)}${e.end_time ? "–" + hhmm(e.end_time) : "〜"}` : "";
const nullIf = v => (v === "" ? null : v);

// ---------- ログイン ----------
async function applySession(session) {
  const on = !!session;
  $("login").hidden = on; $("app").hidden = true; $("who").hidden = !on;
  if (!on) { $("who-mail").textContent = ""; return; }
  const admin = must(await db.from("admins").select("user_id").eq("user_id", session.user.id).maybeSingle());
  if (!admin) {
    await db.auth.signOut();
    $("login-msg").textContent = "このアカウントには管理権限がありません。";
    return;
  }
  $("who-mail").textContent = session.user.email;
  $("app").hidden = false;
  await init();
}

$("login-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    $("login-msg").textContent = "";
    const { data, error } = await db.auth.signInWithPassword({ email: $("login-mail").value.trim(), password: $("login-pass").value });
    if (error) { $("login-msg").textContent = "メールアドレスまたはパスワードが違います。"; return; }
    $("login-pass").value = "";
    await applySession(data.session);
  });
});
$("logout").onclick = () => guard(async () => {
  await db.auth.signOut();
  $("login").hidden = false; $("app").hidden = true;
  $("who").hidden = true; $("who-mail").textContent = "";
});

// ---------- 初期化 ----------
async function loadTypes() {
  types = must(await db.from("event_types").select("*").order("sort_order"));
  typeMap = new Map(types.map(t => [t.name, t]));
  document.querySelectorAll(".type-select").forEach(sel => {
    const v = sel.value;
    sel.innerHTML = types.map(t => `<option value="${esc(t.name)}">${symOf(t.name)} ${esc(t.name)}</option>`).join("");
    if (v) sel.value = v;
  });
  renderTypes();
}

async function init() {
  $("r-wd").innerHTML = DOW.map((d, i) => `<label><input type="checkbox" value="${i}"> ${d}</label>`).join("");
  $("ev-month").value = `${cur.y}-${pad(cur.m + 1)}`;
  await loadTypes();
  await refreshEvents();
}

document.querySelectorAll("#tabs button").forEach(b => b.onclick = () => {
  document.querySelectorAll("#tabs button").forEach(x => x.classList.toggle("active", x === b));
  document.querySelectorAll(".panel").forEach(p => { p.hidden = p.id !== "tab-" + b.dataset.tab; });
  if (b.dataset.tab === "log") guard(refreshLog);
});

// ---------- 予定の一覧・編集 ----------
const selected = new Set();     // 選択中の予定 id
let shownMonth = null;          // いま一覧に出している月（月が変わったら選択をクリア）
const listRows = () => $("ev-list")._rows || new Map();
const selRows = () => [...selected].map(id => listRows().get(id)).filter(Boolean);

async function refreshEvents() {
  const [y, m] = $("ev-month").value.split("-").map(Number);
  cur = { y, m: m - 1 };
  const data = must(await db.from("events").select("*")
    .gte("event_date", monthStart(cur.y, cur.m)).lte("event_date", monthEnd(cur.y, cur.m))
    .order("event_date").order("start_time", { ascending: true, nullsFirst: true }));
  const rows = new Map(data.map(e => [e.id, e]));
  $("ev-list")._rows = rows;
  // 月を切り替えたら選択をクリア。同じ月の再読み込みなら、残っている予定の選択だけ引き継ぐ
  const month = `${y}-${m}`;
  if (month !== shownMonth) selected.clear();
  else [...selected].forEach(id => { if (!rows.has(id)) selected.delete(id); });
  shownMonth = month;

  if (!data.length) { $("ev-list").innerHTML = `<p class="status">この月の予定はありません。</p>`; updateSelectionUI(); return; }
  $("ev-list").innerHTML = `<table><thead><tr>
    <th class="chk"><label class="chk-label" title="全て選択"><input type="checkbox" id="ev-check-all"><span class="vh">全て選択</span></label></th>
    <th>日付</th><th>種別</th><th>内容</th><th>時間</th><th>状態</th><th>操作</th></tr></thead><tbody>${
    data.map(e => `<tr class="${e.is_published ? "" : "draft"}" data-id="${e.id}">
      <td class="chk"><label class="chk-label"><input type="checkbox" class="row-check" aria-label="${esc(fmtDate(e.event_date))} ${esc(e.type)} ${esc(e.title)} を選択"></label></td>
      <td>${fmtDate(e.event_date)}</td>
      <td><button type="button" class="chip-btn" data-act="pick-type" title="同じ種別の予定をすべて選択">${chipHTML({ type: e.type, title: e.type }, typeMap)}</button></td>
      <td>${esc(e.title)}${e.note ? `<br><small>📝 ${esc(e.note)}</small>` : ""}</td>
      <td>${timeText(e)}</td>
      <td><button type="button" class="state ${e.is_published ? "pub" : "draft"}" data-act="toggle" title="クリックで切り替え">${e.is_published ? "● 公開中" : "○ 下書き"}</button></td>
      <td class="actions"><button type="button" class="btn small" data-act="edit">編集</button><button type="button" class="btn small danger" data-act="del">削除</button></td></tr>`).join("")}</tbody></table>`;
  updateSelectionUI();
}

// 選択状態を画面に反映（件数・ツールバー・行のハイライト・全選択チェックの checked/indeterminate）
function updateSelectionUI() {
  const ids = [...listRows().keys()];
  const n = ids.filter(id => selected.has(id)).length;
  $("sel-count").textContent = selected.size;
  $("ev-select-bar").hidden = selected.size === 0;
  const all = $("ev-check-all");
  for (const box of [all, $("sel-all")]) {
    if (!box) continue;
    box.checked = ids.length > 0 && n === ids.length;
    box.indeterminate = n > 0 && n < ids.length;
  }
  $("ev-list").querySelectorAll("tr[data-id]").forEach(tr => {
    const on = selected.has(tr.dataset.id);
    tr.classList.toggle("selected", on);
    tr.querySelector(".row-check").checked = on;
  });
}

function setAll(on) {
  listRows().forEach((_, id) => (on ? selected.add(id) : selected.delete(id)));
  updateSelectionUI();
}
$("sel-all").addEventListener("change", e => setAll(e.target.checked));

function pickType(type) {
  const same = [...listRows().values()].filter(e => e.type === type).map(e => e.id);
  const already = same.length === selected.size && same.every(id => selected.has(id));
  selected.clear();
  if (!already) same.forEach(id => selected.add(id));     // もう一度押すと解除
  updateSelectionUI();
  toast(already ? "選択を解除しました" : `この月の「${type}」${same.length} 件を選択しました`);
}

$("ev-list").addEventListener("change", ev => {
  const t = ev.target;
  if (t.id === "ev-check-all") setAll(t.checked);
  else if (t.classList.contains("row-check")) {
    const id = t.closest("tr").dataset.id;
    if (t.checked) selected.add(id); else selected.delete(id);
    updateSelectionUI();
  }
});

$("ev-list").addEventListener("click", ev => {
  const b = ev.target.closest("[data-act]"); if (!b) return;
  const id = b.closest("tr").dataset.id, e = listRows().get(id);
  guard(async () => {
    if (b.dataset.act === "pick-type") pickType(e.type);
    else if (b.dataset.act === "edit") openForm(e);
    else if (b.dataset.act === "toggle") {
      must(await db.from("events").update({ is_published: !e.is_published }).eq("id", id).select());
      toast(e.is_published ? "下書きに戻しました" : "公開しました");
      await refreshEvents();
    } else if (b.dataset.act === "del") {
      if (!confirm(`次の予定を削除します。元に戻せません。\n\n${fmtDate(e.event_date)} ${e.type} ${e.title}\n\nよろしいですか？`)) return;
      must(await db.from("events").delete().eq("id", id).select());
      toast("削除しました"); await refreshEvents();
    }
  });
});

// ---------- 選択した予定の一括操作 ----------
const chunksOf = (a, n = 100) => Array.from({ length: Math.ceil(a.length / n) }, (_, i) => a.slice(i * n, i * n + n));
// ids を分割して fn を実行し、処理された件数の合計を返す（RLS などで 0 件になったときに気づけるように件数を見る）
async function inChunks(ids, fn) {
  let total = 0;
  for (const c of chunksOf(ids)) total += must(await fn(c)).length;
  if (total !== ids.length) throw new Error(`${ids.length} 件中 ${total} 件のみ処理されました。一覧を更新して確認してください。`);
  return total;
}
const summary = rows => rows.slice(0, 5).map(e => `・${fmtDate(e.event_date)} ${e.type} ${e.title}`).join("\n") + (rows.length > 5 ? `\n…ほか ${rows.length - 5} 件` : "");

$("sel-clear").onclick = () => { selected.clear(); updateSelectionUI(); };

// 公開/下書き: 下書きが1件でも混じっていれば全部「公開」、全部公開なら全部「下書き」に揃える
$("bulk-toggle").onclick = () => guard(async () => {
  const rows = selRows(); if (!rows.length) return;
  const target = rows.some(r => !r.is_published);
  const changing = rows.filter(r => r.is_published !== target);
  const label = target ? "公開" : "下書き";
  if (!confirm(`選択中の ${rows.length} 件のうち ${changing.length} 件を「${label}」に変更します。\n\n${summary(changing)}\n\nよろしいですか？`)) return;
  const n = await inChunks(changing.map(r => r.id), c => db.from("events").update({ is_published: target }).in("id", c).select("id"));
  selected.clear(); toast(`${n} 件を${label}にしました`); await refreshEvents();
});

$("bulk-delete").onclick = () => guard(async () => {
  const rows = selRows(); if (!rows.length) return;
  if (!confirm(`選択中の ${rows.length} 件を削除します。元に戻せません（変更履歴には残ります）。\n\n${summary(rows)}\n\nよろしいですか？`)) return;
  const n = await inChunks(rows.map(r => r.id), c => db.from("events").delete().in("id", c).select("id"));
  selected.clear(); toast(`${n} 件を削除しました`); await refreshEvents();
});

// 一括編集ダイアログ（同じ種別だけ。項目ごとのチェックを入れたものだけ反映）
const BULK_IDS = ["b-start", "b-end", "b-title", "b-note", "b-pub"];
const commonValue = (rows, f) => (new Set(rows.map(f)).size === 1 ? f(rows[0]) : "");

function openBulkEditDialog() {
  const rows = selRows(); if (!rows.length) return;
  const kinds = [...new Set(rows.map(r => r.type))];
  if (kinds.length > 1) { toast(`種別が混在しているため一括編集できません（${kinds.join("、")}）。同じ種別だけを選んでください。`, true); return; }
  $("bulk-title").textContent = `『${kinds[0]}』の一括編集`;
  $("bulk-summary").innerHTML = `${chipHTML({ type: kinds[0], title: kinds[0] }, typeMap)} <strong>${rows.length}件</strong>の予定を編集します。変更する項目にチェックを入れてください。`;
  $("b-start").value = commonValue(rows, r => hhmm(r.start_time));
  $("b-end").value = commonValue(rows, r => hhmm(r.end_time));
  $("b-title").value = commonValue(rows, r => r.title);
  $("b-note").value = commonValue(rows, r => r.note);
  $("b-pub").value = rows.every(r => !r.is_published) ? "0" : "1";
  BULK_IDS.forEach(id => { $(id + "-on").checked = false; $(id).disabled = true; });
  $("ev-bulk-dlg").showModal();
}
$("bulk-edit").onclick = openBulkEditDialog;
$("bulk-cancel").onclick = () => $("ev-bulk-dlg").close();
$("ev-bulk-fields").addEventListener("change", e => {
  if (e.target.type === "checkbox") $(e.target.id.replace(/-on$/, "")).disabled = !e.target.checked;
});

$("ev-bulk-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const rows = selRows();
    const kinds = [...new Set(rows.map(r => r.type))];
    if (!rows.length) throw new Error("選択中の予定がありません。");
    if (kinds.length > 1) throw new Error(`種別が混在しているため一括編集できません（${kinds.join("、")}）。`);
    const payload = {}, lines = [];
    if ($("b-start-on").checked) { payload.start_time = nullIf($("b-start").value); lines.push(`開始時刻: ${$("b-start").value || "（なし）"}`); }
    if ($("b-end-on").checked) { payload.end_time = nullIf($("b-end").value); lines.push(`終了時刻: ${$("b-end").value || "（なし）"}`); }
    if ($("b-title-on").checked) { payload.title = $("b-title").value.trim() || kinds[0]; lines.push(`内容: ${payload.title}`); }
    if ($("b-note-on").checked) { payload.note = $("b-note").value.trim(); lines.push(`備考: ${payload.note || "（なし）"}`); }
    if ($("b-pub-on").checked) { payload.is_published = $("b-pub").value === "1"; lines.push(`状態: ${payload.is_published ? "公開" : "下書き"}`); }
    if (!lines.length) throw new Error("変更する項目にチェックを入れてください。");
    // 反映後に「終了 < 開始」になる予定があれば、更新前に止める
    const bad = rows.filter(r => {
      const s = "start_time" in payload ? payload.start_time : hhmm(r.start_time) || null;
      const en = "end_time" in payload ? payload.end_time : hhmm(r.end_time) || null;
      return s && en && en < s;
    });
    if (bad.length) throw new Error(`終了時刻が開始時刻より前になる予定が ${bad.length} 件あります（例: ${fmtDate(bad[0].event_date)}）。`);
    if (!confirm(`選択した ${rows.length} 件（${kinds[0]}）を、次のとおり更新します。\n\n${lines.map(l => "・" + l).join("\n")}\n\n対象:\n${summary(rows)}\n\nよろしいですか？`)) return;
    const n = await inChunks(rows.map(r => r.id), c => db.from("events").update(payload).in("id", c).select("id"));
    $("ev-bulk-dlg").close(); selected.clear();
    toast(`${n} 件を更新しました`); await refreshEvents();
  });
});

function shiftMonth(d) {
  const dt = new Date(cur.y, cur.m + d, 1);
  $("ev-month").value = `${dt.getFullYear()}-${pad(dt.getMonth() + 1)}`;
  guard(refreshEvents);
}
$("ev-prev").onclick = () => shiftMonth(-1);
$("ev-next").onclick = () => shiftMonth(1);
$("ev-month").onchange = () => { if ($("ev-month").value) guard(refreshEvents); };

function openForm(e) {
  editingId = e ? e.id : null;
  $("ev-dlg-title").textContent = e ? "予定を編集" : "予定を追加";
  $("e-date").value = e ? e.event_date : ymd(cur.y, cur.m, 1);
  $("e-type").value = e ? e.type : types[0]?.name;
  $("e-title").value = e ? e.title : "";
  $("e-start").value = e ? hhmm(e.start_time) : "";
  $("e-end").value = e ? hhmm(e.end_time) : "";
  $("e-note").value = e ? e.note : "";
  $("e-pub").checked = e ? e.is_published : true;
  $("ev-dlg").showModal();
}
$("ev-add").onclick = () => openForm(null);
$("ev-cancel").onclick = () => $("ev-dlg").close();
$("ev-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const row = {
      event_date: $("e-date").value, type: $("e-type").value, title: $("e-title").value.trim() || $("e-type").value,
      start_time: nullIf($("e-start").value), end_time: nullIf($("e-end").value),
      note: $("e-note").value.trim(), is_published: $("e-pub").checked,
    };
    if (row.start_time && row.end_time && row.end_time < row.start_time) throw new Error("終了時刻は開始時刻以降にしてください。");
    if (editingId) must(await db.from("events").update(row).eq("id", editingId).select());
    else must(await db.from("events").insert(row).select());
    $("ev-dlg").close(); toast("保存しました");
    $("ev-month").value = row.event_date.slice(0, 7);
    await refreshEvents();
  });
});

// ---------- 一括登録（繰り返し / 期間） ----------
const parseYMD = k => { const [y, m, d] = k.split("-").map(Number); return new Date(y, m - 1, d); };
const fmtYMD = d => ymd(d.getFullYear(), d.getMonth(), d.getDate());

function datesBetween(from, to, allow) {
  const a = parseYMD(from), b = parseYMD(to);
  if (b < a) throw new Error("終了日は開始日以降にしてください。");
  if ((b - a) / 864e5 > 800) throw new Error("期間が長すぎます（最大 約2年）。");
  const out = [];
  for (const d = new Date(a); d <= b; d.setDate(d.getDate() + 1)) if (allow(d)) out.push(fmtYMD(d));
  return out;
}

async function bulkInsert(dates, base, label) {
  if (!dates.length) throw new Error("登録対象の日がありません。条件を確認してください。");
  const list = dates.length <= 6 ? dates.join(", ") : `${dates.slice(0, 3).join(", ")} … ${dates.slice(-2).join(", ")}`;
  if (!confirm(`${label}\n${dates.length} 件の予定を登録します。\n${list}\n\nよろしいですか？（登録後は一覧から個別に削除できます）`)) return false;
  const rows = dates.map(d => ({ ...base, event_date: d }));
  for (let i = 0; i < rows.length; i += 200) must(await db.from("events").insert(rows.slice(i, i + 200)).select("id"));
  return true;
}

function baseRow(p) {
  const s = nullIf($(p + "-start").value), e = nullIf($(p + "-end").value);
  if (s && e && e < s) throw new Error("終了時刻は開始時刻以降にしてください。");
  const type = $(p + "-type").value;
  return { type, title: $(p + "-title").value.trim() || type, start_time: s, end_time: e, note: $(p + "-note").value.trim(), is_published: $(p + "-pub").checked };
}

$("repeat-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const wds = [...$("r-wd").querySelectorAll("input:checked")].map(i => +i.value);
    if (!wds.length) throw new Error("曜日を1つ以上選んでください。");
    const bad = [], ex = new Set();
    $("r-ex").value.split(/[\s,、]+/).filter(Boolean).forEach(t => { const k = normDate(t); k ? ex.add(k) : bad.push(t); });
    if (bad.length) throw new Error("除外日の形式が読み取れません: " + bad.join(", "));
    const dates = datesBetween($("r-from").value, $("r-to").value, d => wds.includes(d.getDay()) && !ex.has(fmtYMD(d)));
    const ok = await bulkInsert(dates, baseRow("r"), `毎週 ${wds.map(i => DOW[i]).join("・")}（${$("r-from").value} 〜 ${$("r-to").value}、除外 ${ex.size} 日）`);
    if (ok) { toast(`${dates.length} 件登録しました`); await refreshEvents(); }
  });
});

$("range-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const noSun = $("g-nosun").checked;
    const dates = datesBetween($("g-from").value, $("g-to").value, d => !(noSun && d.getDay() === 0));
    const ok = await bulkInsert(dates, baseRow("g"), `期間登録（${$("g-from").value} 〜 ${$("g-to").value}）`);
    if (ok) { toast(`${dates.length} 件登録しました`); await refreshEvents(); }
  });
});

// ---------- 種別の色 ----------
function renderTypes() {
  $("type-list").innerHTML = types.map(t => `<div class="type-row" data-name="${esc(t.name)}">
    ${chipHTML({ type: t.name, title: t.name }, typeMap)}
    <span class="name">${esc(t.name)}</span>
    <input type="color" value="${esc(t.color)}" aria-label="${esc(t.name)}の色">
    <button type="button" class="btn small">保存</button></div>`).join("");
}
$("type-list").addEventListener("click", ev => {
  const btn = ev.target.closest("button"); if (!btn) return;
  const row = btn.closest(".type-row"), name = row.dataset.name, color = row.querySelector("input").value;
  guard(async () => {
    must(await db.from("event_types").update({ color }).eq("name", name).select());
    toast(`「${name}」の色を保存しました`); await loadTypes(); await refreshEvents();
  });
});

// ---------- CSV ----------
const CSV_HEAD = ["日付", "種別", "内容", "開始時刻", "終了時刻", "備考", "公開"];

async function fetchAllEvents() {
  const all = [];
  for (let from = 0; ; from += 1000) {
    const data = must(await db.from("events").select("*").order("event_date").order("start_time", { nullsFirst: true }).range(from, from + 999));
    all.push(...data);
    if (data.length < 1000) return all;
  }
}

async function exportCSV() {
  const data = await fetchAllEvents();
  const csv = toCSV([CSV_HEAD, ...data.map(e => [e.event_date, e.type, e.title, hhmm(e.start_time), hhmm(e.end_time), e.note, e.is_published ? "公開" : "下書き"])]);
  const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
  const a = document.createElement("a");
  const t = new Date();
  a.href = URL.createObjectURL(blob);
  a.download = `sekigaku-schedule-${t.getFullYear()}${pad(t.getMonth() + 1)}${pad(t.getDate())}.csv`;
  document.body.append(a); a.click(); a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
  return data.length;
}
$("csv-export").onclick = () => guard(async () => toast(`${await exportCSV()} 件を書き出しました`));

function csvMsg(text, ok) { const m = $("csv-msg"); m.textContent = text; m.classList.toggle("ok", !!ok); }

$("csv-import").onclick = () => guard(async () => {
  csvMsg("");
  const file = $("csv-file").files[0];
  if (!file) throw new Error("CSVファイルを選んでください。");
  const rows = parseCSV(await file.text());
  if (rows.length < 2) throw new Error("データ行がありません。");
  const head = rows[0].map(h => h.trim()), idx = n => head.indexOf(n);
  if (idx("日付") < 0 || idx("種別") < 0) throw new Error("見出し行に「日付」「種別」の列が必要です。");
  const errors = [], out = [];
  rows.slice(1).forEach((r, i) => {
    const line = i + 2, get = n => (idx(n) >= 0 ? (r[idx(n)] ?? "").trim() : "");
    const date = normDate(get("日付")), type = get("種別"), s = normTime(get("開始時刻")), e = normTime(get("終了時刻"));
    if (!date) errors.push(`${line}行目: 日付が不正`);
    else if (!typeMap.has(type)) errors.push(`${line}行目: 種別「${type}」は未登録`);
    else if (s === null || e === null) errors.push(`${line}行目: 時刻が不正`);
    else if (s && e && e < s) errors.push(`${line}行目: 終了時刻が開始時刻より前`);
    else out.push({ event_date: date, type, title: get("内容") || type, start_time: nullIf(s), end_time: nullIf(e), note: get("備考"), is_published: ["公開", "true", "1", "○"].includes(get("公開")) });
  });
  if (errors.length) { csvMsg(`読み込めませんでした（何も変更していません）:\n${errors.slice(0, 8).join(" / ")}${errors.length > 8 ? ` ほか${errors.length - 8}件` : ""}`); return; }

  const replace = $("csv-replace").checked;
  if (replace) {
    if (prompt(`既存の予定をすべて削除し、CSVの ${out.length} 件で置き換えます。\n削除前に現在のデータを自動でCSVに書き出します。\n続けるには「全削除」と入力してください。`) !== "全削除") return;
    await exportCSV();
    must(await db.from("events").delete().gte("event_date", "1900-01-01").select("id"));
  } else if (!confirm(`${out.length} 件の予定を追加します（既存の予定はそのまま残ります。同じ内容を重複して登録しないようご注意ください）。`)) return;

  for (let i = 0; i < out.length; i += 200) must(await db.from("events").insert(out.slice(i, i + 200)).select("id"));
  csvMsg(`${out.length} 件を${replace ? "置き換えました" : "追加しました"}。`, true);
  $("csv-file").value = "";
  await refreshEvents();
});

// ---------- 変更履歴 ----------
const KEYS = { event_date: "日付", type: "種別", title: "内容", start_time: "開始", end_time: "終了", note: "備考", is_published: "公開", color: "色", sort_order: "並び順" };
const OPS = { INSERT: "追加", UPDATE: "変更", DELETE: "削除" };
const show = v => (v === null || v === undefined || v === "" ? "（なし）" : v === true ? "公開" : v === false ? "下書き" : String(v));

async function refreshLog() {
  const data = must(await db.from("audit_log").select("*").order("at", { ascending: false }).limit(100));
  if (!data.length) { $("log-list").innerHTML = `<p class="status">履歴はまだありません。</p>`; return; }
  $("log-list").innerHTML = data.map(l => {
    const d = l.new_data || l.old_data || {};
    const what = l.table_name === "events" ? `予定 ${d.event_date} ${d.type} ${d.title}` : `種別「${d.name}」`;
    let detail = "";
    if (l.op === "UPDATE") {
      detail = Object.keys(l.new_data).filter(k => k !== "updated_at" && JSON.stringify(l.new_data[k]) !== JSON.stringify(l.old_data[k]))
        .map(k => `${KEYS[k] || k}: ${show(l.old_data[k])} → ${show(l.new_data[k])}`).join("\n");
    } else {
      detail = Object.entries(d).filter(([k]) => !["id", "created_at", "updated_at"].includes(k)).map(([k, v]) => `${KEYS[k] || k}: ${show(v)}`).join("\n");
    }
    return `<div class="log-item"><div class="when">${new Date(l.at).toLocaleString("ja-JP", { timeZone: "Asia/Tokyo" })}</div>
      <span class="op ${l.op}">${OPS[l.op] || l.op}</span>${esc(what)}
      <details><summary>詳細（変更前後）</summary><pre>${esc(detail)}</pre></details></div>`;
  }).join("");
}
$("log-refresh").onclick = () => guard(refreshLog);

// ---------- 起動 ----------
(async function boot() {
  if (!db) { $("login").hidden = false; $("login-msg").textContent = "接続設定（js/config.js）が未入力です。"; return; }
  await guard(async () => {
    const { data } = await db.auth.getSession();
    if (data.session) await applySession(data.session); else $("login").hidden = false;
  });
  db.auth.onAuthStateChange(ev => { if (ev === "SIGNED_OUT") { $("login").hidden = false; $("app").hidden = true; $("who").hidden = true; $("who-mail").textContent = ""; } });
})();
