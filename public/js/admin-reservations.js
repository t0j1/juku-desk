"use strict";
// 管理画面：送迎予約（承認待ち・日ごとの予約）と、通知（画面のポップアップ・音・ブラウザの通知）。
// admin.js / admin-pickup.js のあとに読み込む。新しい予約は Realtime ですぐに受け取り、つながらないときは15秒ごとの確認で拾う。

const RES_SELECT = "*, students(name, grade, phone)";
const GROUP_SELECT = "*, pickup_reservations(id, status, pickup_time, party_size, students(name, grade))";
const NOTIFY_KEY = "pickup_notify_on";
const POLL_MS = 15000;

let pkView = "pending";
let pendingRows = [];
let pendingGroups = [];     // 承認待ちの予約がある日の便
let dayRows = [];
let dayGroups = [];
let dayProposals = [];      // その日の調整中の便の打診
let dayWindows = [];        // その日の送迎時間帯（日付ごとの調整、または曜日の設定）
let dayOverrides = [];      // その日の日付ごとの調整（無ければ空）
let proposingGroups = [];   // 今日以降の調整中の便（承認待ちの画面に出す）
const cpSelected = new Set();   // 日ごとの予約で、相乗り調整に選んだ予約
let cpRows = [];            // 相乗り調整ダイアログの予約
let approving = null;       // 承認ダイアログの予約
let rejecting = null;       // 却下ダイアログの予約
let pkChannel = null;
let pollTimer = null;
let pkStarted = false;
const knownPending = new Set();   // 通知済み（または起動時からある）未承認の予約
const localChanges = new Set();   // この画面で操作した予約（自分の操作は通知しない）

const todayJST = () => new Date().toLocaleDateString("sv-SE", { timeZone: "Asia/Tokyo" });   // YYYY-MM-DD
const nowJSTMin = () => { const [h, m] = new Date().toLocaleTimeString("en-GB", { timeZone: "Asia/Tokyo", hour12: false }).split(":").map(Number); return h * 60 + m; };
const addDays = (k, n) => { const d = parseYMD(k); d.setDate(d.getDate() + n); return fmtYMD(d); };
const nameOf = r => (r.students ? `${r.students.name}さん` : "（生徒不明）");
const gradeOf = r => (r.students?.grade ? `（${r.students.grade}）` : "");
const activeMembers = g => (g.pickup_reservations || []).filter(m => m.status === "pending" || m.status === "approved");
const sizeOf = r => r.party_size || 1;                               // 乗る人数（本人を含む）
const sumSize = rows => rows.reduce((n, r) => n + sizeOf(r), 0);
const loadOf = g => sumSize(activeMembers(g));                        // 便に乗る人数の合計
const seatsLeft = g => g.max_capacity - loadOf(g);
const sizeText = r => (sizeOf(r) > 1 ? `・${sizeOf(r)}名` : "");
const tripEnd = g => fromMin(toMin(hhmm(g.approved_time)) + g.trip_minutes);
const minutesUntil = r => (r.pickup_date === todayJST() ? toMin(hhmm(r.pickup_time)) - nowJSTMin() : Infinity);

// ---------- 起動 ----------
async function initPickupAdmin() {
  if (pkStarted) return;
  pkStarted = true;
  $("pk-date").value = todayJST();
  updateNotifyButton();
  unlockAudio();   // ログインのクリックの直後なら、そのまま音を使える
  const rows = await fetchPending();
  rows.forEach(r => knownPending.add(r.id));   // 起動時にすでにあるものは通知しない
  applyPending(rows);
  subscribeRealtime();
  pollTimer = setInterval(() => guard(pollPending), POLL_MS);
}
// 管理画面にログインし終わってからこのファイルが読み込まれた場合
if (!$("app").hidden) guard(initPickupAdmin);

db?.auth.onAuthStateChange(ev => {
  if (ev !== "SIGNED_OUT") return;
  pkStarted = false;
  clearInterval(pollTimer);
  if (pkChannel) { db.removeChannel(pkChannel); pkChannel = null; }
  knownPending.clear();
  closeAlert();
  setBadge(0);
});

document.querySelectorAll("#tabs button").forEach(b => b.addEventListener("click", () => {
  if (b.dataset.tab === "pickups") guard(refreshPickups);
  if (b.dataset.tab === "events") guard(refreshEvents);   // 送迎を承認したあとに戻ったとき、便を反映する
}));
$("pk-refresh").onclick = () => guard(refreshPickups);
document.querySelectorAll("#tab-pickups .seg button").forEach(b => b.onclick = () => { setView(b.dataset.view); guard(refreshPickups); });

function setView(v) {
  pkView = v;
  document.querySelectorAll("#tab-pickups .seg button").forEach(b => {
    const on = b.dataset.view === v;
    b.classList.toggle("active", on); b.setAttribute("aria-pressed", String(on));
  });
  $("pk-pending").hidden = v !== "pending";
  $("pk-day").hidden = v !== "day";
  updatePickupHead();
}
const WEEKDAY = ["日曜日", "月曜日", "火曜日", "水曜日", "木曜日", "金曜日", "土曜日"];
function updatePickupHead() {
  $("pk-crumb").textContent = pkView === "pending" ? "承認待ち" : "日ごとの予約";
  if (pkView === "pending") {
    $("pk-title").innerHTML = `承認待ち<small>${pendingRows.length}件</small>`;
  } else {
    const dt = parseYMD($("pk-date").value || todayJST());
    $("pk-title").innerHTML = `${dt.getMonth() + 1}月${dt.getDate()}日<small>${WEEKDAY[dt.getDay()]}</small>`;
  }
}
function openPickupsTab(view, date) {
  document.querySelector('#tabs button[data-tab="pickups"]').click();   // タブの切り替えは admin.js の処理に任せる
  if (date) $("pk-date").value = date;
  setView(view);
  guard(refreshPickups);
}

const refreshPickups = async () => (pkView === "pending" ? refreshPending() : refreshDay());

// ---------- データ ----------
async function fetchPending() {
  return must(await db.from("pickup_reservations").select(RES_SELECT)
    .eq("status", "pending").is("group_id", null).gte("pickup_date", todayJST())
    .order("pickup_date").order("pickup_time").order("created_at"));
}
async function fetchGroups(dates) {
  if (!dates.length) return [];
  return must(await db.from("pickup_groups").select(GROUP_SELECT)
    .in("pickup_date", dates).neq("status", "cancelled").order("pickup_date").order("approved_time"));
}
function applyPending(rows) {
  pendingRows = rows;
  setBadge(rows.length);
  if (pkView === "pending") updatePickupHead();
}
function setBadge(n) {
  const b = $("pk-badge");
  b.hidden = !n; b.textContent = n;
  $("pk-count").textContent = n ? `(${n})` : "";
  if (!blinkTimer) document.title = (n ? `(${n}) ` : "") + "碩学館 管理画面";
}

// ---------- 「予定」タブに重ねる送迎（admin.js の refreshEvents から呼ばれる） ----------
async function fetchMonthPickups(from, to) {
  const groups = must(await db.from("pickup_groups")
    .select("id, pickup_date, approved_time, trip_minutes, pickup_reservations(status, party_size, students(name))")
    .eq("status", "confirmed").gte("pickup_date", from).lte("pickup_date", to)
    .order("pickup_date").order("approved_time"));
  return groups
    .map(g => {
      const on = (g.pickup_reservations || []).filter(r => r.status === "approved");
      return { ...g, riders: on.map(r => `${r.students?.name || "（不明）"}さん${sizeOf(r) > 1 ? `（${sizeOf(r)}名）` : ""}`), total: sumSize(on) };
    })
    .filter(g => g.riders.length);
}
function pickupRowHTML(g) {
  return `<tr class="pickup-row" data-pickup-date="${esc(g.pickup_date)}">
    <td class="chk"></td>
    <td>${fmtDay(g.pickup_date)}</td>
    <td><span class="chip pickup-chip"><span class="sym" aria-hidden="true">🚗</span>送迎</span></td>
    <td>送迎 ${g.riders.map(esc).join(", ")}（${g.total}名）</td>
    <td>${hhmm(g.approved_time)}–${tripEnd(g)}</td>
    <td><span class="state readonly" title="送迎予約タブで管理します">管理画面のみ</span></td>
    <td class="actions"><button type="button" class="btn small" data-act="open-pickup">送迎予約で開く</button></td></tr>`;
}
$("ev-show-pickup").addEventListener("change", () => guard(refreshEvents));

// ---------- 表示の部品（乗客の行・空の表示） ----------
const PHONE_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M22 16.9v3a2 2 0 0 1-2.2 2 19.8 19.8 0 0 1-8.6-3.1 19.5 19.5 0 0 1-6-6A19.8 19.8 0 0 1 2.1 4.2 2 2 0 0 1 4.1 2h3a2 2 0 0 1 2 1.7c.1.9.4 1.8.7 2.7a2 2 0 0 1-.5 2.1L8 9.8a16 16 0 0 0 6 6l1.3-1.3a2 2 0 0 1 2.1-.4c.9.3 1.8.6 2.7.7a2 2 0 0 1 1.7 2z"/></svg>';
const CHECK_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>';
const initialOf = r => (r.students?.name || "?").trim().charAt(0);
const receivedAt = r => new Date(r.created_at).toLocaleString("ja-JP", { timeZone: "Asia/Tokyo", month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" });
const emptyOk = text => `<div class="empty-ok"><span class="ok-mark">${CHECK_SVG}</span>${esc(text)}</div>`;
const callBtn = r => (r.students?.phone ? `<a class="btn small btn-call" href="tel:${esc(r.students.phone)}">${PHONE_SVG}発信</a>` : "");

// 乗客（生徒）1人の行。便・未承認・承認待ちで共通
function riderHTML(r, { sub, check = false, extra = "", actions = "" }) {
  const phone = r.students?.phone;
  return `<li class="rider${check ? "" : " no-check"}${cpSelected.has(r.id) ? " selected" : ""}" data-id="${r.id}">
    ${check ? `<label class="chk-label"><input type="checkbox" class="cp-check" aria-label="${esc(nameOf(r))}を相乗り調整に選ぶ"${cpSelected.has(r.id) ? " checked" : ""}></label>` : ""}
    <span class="avatar" aria-hidden="true">${esc(initialOf(r))}</span>
    <div class="rider-info">
      <div><span class="rider-name">${esc(r.students?.name || "（生徒不明）")} さん</span>${r.students?.grade ? `<span class="grade-tag">${esc(r.students.grade)}</span>` : ""}${sizeOf(r) > 1 ? `<span class="grade-tag party">${sizeOf(r)}名</span>` : ""}${extra}</div>
      <div class="rider-sub">${sub}${phone ? ` · <a href="tel:${esc(phone)}">${esc(phone)}</a>` : ""}</div>
      ${r.notes ? `<div class="rider-note">📝 ${esc(r.notes)}</div>` : ""}
    </div>
    <div class="rider-actions">${actions}</div>
  </li>`;
}
// 未承認の予約の行（承認・時刻や便を選ぶ・却下）
function pendingRiderHTML(r, groups, check = false) {
  const left = minutesUntil(r);
  const g = sameTimeGroup(r, groups);
  const extra = (left <= 60 ? ` <span class="urgent">⚠ あと${Math.max(left, 0)}分</span>` : "")
    + (g ? ` <span class="join">${hhmm(g.approved_time)} の便に相乗り（残り${seatsLeft(g)}席）</span>` : "");
  return riderHTML(r, {
    sub: `希望 ${hhmm(r.pickup_time)}${sizeText(r)} · 受付 ${receivedAt(r)}`, check, extra,
    actions: `${callBtn(r)}
      <button type="button" class="btn small primary" data-act="approve"${g && seatsLeft(g) < sizeOf(r) ? ' disabled title="同じ時刻の便に、この人数は乗れません"' : ""}>承認</button>
      <button type="button" class="btn small" data-act="approve-choose">時刻・便を選ぶ</button>
      <button type="button" class="btn small danger" data-act="reject">却下</button>`,
  });
}

// ---------- 承認待ち ----------
async function refreshPending() {
  applyPending(await fetchPending());
  const [groups, proposing] = await Promise.all([
    fetchGroups([...new Set(pendingRows.map(r => r.pickup_date))]),
    db.from("pickup_groups").select(`${GROUP_SELECT}, pickup_proposals(reservation_id, response, expires_at)`)
      .eq("status", "proposing").gte("pickup_date", todayJST()).order("pickup_date").order("approved_time").then(must),
  ]);
  pendingGroups = groups; proposingGroups = proposing;
  const dates = [...new Set(pendingRows.map(r => r.pickup_date))];
  const list = pendingRows.length
    ? dates.map(d => `<section class="date-group"><p class="date-label">${fmtDay(d)}</p><ul class="riders">${
        pendingRows.filter(r => r.pickup_date === d).map(r => pendingRiderHTML(r, pendingGroups)).join("")}</ul></section>`).join("")
    : emptyOk("承認待ちの予約はありません");
  const adjusting = proposingGroups.length ? `<section class="card adjusting">
      <div class="card-head"><h2>相乗りの調整中</h2><span class="count">${proposingGroups.length}便</span></div>
      <ul>${proposingGroups.map(g => {
        const answers = proposalSummary(g, g.pickup_proposals || []);
        return `<li><button type="button" class="linklike" data-open-day="${esc(g.pickup_date)}">${fmtDay(g.pickup_date)} ${hhmm(g.approved_time)} 発</button>
          ${activeMembers(g).map(m => esc(m.students?.name || "") + "さん").join("・")}　${answers.text}${answers.needsAction ? ` <span class="urgent">要対応</span>` : ""}</li>`;
      }).join("")}</ul></section>` : "";
  $("pk-pending").innerHTML = `<section class="card">
      <div class="card-head"><h2>承認待ちの予約</h2><span class="count">${pendingRows.length}件</span></div>${list}</section>${adjusting}`;
  updatePickupHead();
}
// 打診の回答状況 { text: "承認2・待ち1", needsAction: 辞退か期限切れがある }
function proposalSummary(g, proposals) {
  const members = new Set(activeMembers(g).map(m => m.id));
  const mine = proposals.filter(p => members.has(p.reservation_id)).map(p => effectiveResponse(p));
  const n = k => mine.filter(x => x === k).length;
  const parts = [["accepted", "承認"], ["waiting", "待ち"], ["declined", "辞退"], ["expired", "期限切れ"]].filter(([k]) => n(k)).map(([k, l]) => `${l}${n(k)}`);
  return { text: parts.join("・"), needsAction: n("declined") + n("expired") > 0 };
}
const effectiveResponse = p => (p.response === "waiting" && new Date(p.expires_at) <= new Date() ? "expired" : p.response);
$("pk-pending").addEventListener("click", ev => {
  const b = ev.target.closest("[data-open-day]"); if (b) openPickupsTab("day", b.dataset.openDay);
});

function sameTimeGroup(r, groups) {
  return groups.find(g => g.pickup_date === r.pickup_date && g.status === "confirmed" && hhmm(g.approved_time) === hhmm(r.pickup_time));
}
// 承認待ち・日ごとの予約で共通の操作
function onReservationAction(ev, rows, groups) {
  const b = ev.target.closest("[data-act]"); if (!b) return;
  const r = rows.find(x => x.id === b.closest("[data-id]")?.dataset.id);
  if (!r) return;
  guard(async () => {
    if (b.dataset.act === "approve") await quickApprove(r, groups);
    else if (b.dataset.act === "approve-choose") openApproveDialog(r, groups);
    else if (b.dataset.act === "reject") openRejectDialog(r);
    else if (b.dataset.act === "cancel-res") await adminCancel(r);
  });
}
$("pk-pending").addEventListener("click", ev => onReservationAction(ev, pendingRows, pendingGroups));

async function quickApprove(r, groups) {
  const g = sameTimeGroup(r, groups);
  const what = g ? `${hhmm(g.approved_time)} の便（${activeMembers(g).map(m => m.students?.name).join("・")}さん）に相乗りで承認` : `${hhmm(r.pickup_time)} 発で承認`;
  if (!confirm(`${fmtDay(r.pickup_date)} ${nameOf(r)}の予約を、${what}します。\n\nよろしいですか？`)) return;
  await approve(r, null, g?.id ?? null);
}
async function approve(r, time, groupId) {
  localChanges.add(r.id);
  must(await db.rpc("admin_approve_reservation", { p_reservation_id: r.id, p_time: time, p_group: groupId }));
  knownPending.delete(r.id);
  toast(`${nameOf(r)}の予約を承認しました`);
  await refreshPickups();
}

function openApproveDialog(r, groups) {
  approving = r;
  $("pa-who").textContent = `${fmtDay(r.pickup_date)} ${nameOf(r)}${gradeOf(r)}　希望 ${hhmm(r.pickup_time)} 発${sizeText(r)}`;
  $("pa-time").value = hhmm(r.pickup_time);
  const same = groups.filter(g => g.pickup_date === r.pickup_date && g.status === "confirmed");
  $("pa-groups-box").hidden = !same.length;
  $("pa-groups").innerHTML = same.map(g => {
    const left = seatsLeft(g);
    const differs = hhmm(g.approved_time) !== hhmm(r.pickup_time);
    return `<div class="pa-group"><span><strong>${hhmm(g.approved_time)}</strong>〜${tripEnd(g)}　${activeMembers(g).map(m => esc(m.students?.name || "")).join("・")}さん（${loadOf(g)}/${g.max_capacity}名）</span>
      <span class="actions">${left < sizeOf(r) ? `<button type="button" class="btn small" disabled>${left <= 0 ? "満席" : `残り${left}名`}</button>` : `
        ${differs ? `<button type="button" class="btn small" data-propose-gid="${g.id}" title="生徒に ${hhmm(g.approved_time)} 発でよいか聞きます">打診する</button>` : ""}
        <button type="button" class="btn small primary" data-gid="${g.id}" title="${differs ? "電話などで確認済みのとき" : ""}">この便に入れる</button>`}</span></div>`;
  }).join("");
  $("pk-approve-dlg").showModal();
}
$("pa-cancel").onclick = () => $("pk-approve-dlg").close();
$("pa-new").onclick = () => guard(async () => {
  const t = $("pa-time").value;
  if (!t) throw new Error("出発時刻を入力してください。");
  await approve(approving, t, null);
  $("pk-approve-dlg").close();
});
$("pa-groups").addEventListener("click", ev => {
  const join = ev.target.closest("[data-gid]"), ask = ev.target.closest("[data-propose-gid]");
  if (join) guard(async () => { await approve(approving, null, join.dataset.gid); $("pk-approve-dlg").close(); });
  if (ask) guard(async () => {
    const g = [...pendingGroups, ...dayGroups].find(x => x.id === ask.dataset.proposeGid);
    if (!confirm(`${nameOf(approving)}に、${hhmm(g.approved_time)} 発の便への相乗りを打診します。\n\nよろしいですか？`)) return;
    const r = approving;
    await sendProposal([r], null, g.id);
    $("pk-approve-dlg").close();
  });
});

function openRejectDialog(r) {
  rejecting = r;
  $("pr-who").textContent = `${fmtDay(r.pickup_date)} ${hhmm(r.pickup_time)} 発　${nameOf(r)}${gradeOf(r)}`;
  $("pr-reason").selectedIndex = 0; $("pr-other").value = "";
  $("pk-reject-dlg").showModal();
}
$("pr-cancel").onclick = () => $("pk-reject-dlg").close();
$("pk-reject-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const reason = $("pr-reason").value || $("pr-other").value.trim();
    if (!reason) throw new Error("理由を選ぶか、入力してください。");
    localChanges.add(rejecting.id);
    must(await db.rpc("admin_reject_reservation", { p_reservation_id: rejecting.id, p_reason: reason }));
    knownPending.delete(rejecting.id);
    $("pk-reject-dlg").close(); toast(`${nameOf(rejecting)}の予約を却下しました`);
    await refreshPickups();
  });
});

async function adminCancel(r) {
  if (!confirm(`${fmtDay(r.pickup_date)} ${hhmm(r.approved_time || r.pickup_time)} 発　${nameOf(r)}の予約を取り消します。\n（元に戻せません。生徒には取り消しを連絡してください）\n\nよろしいですか？`)) return;
  localChanges.add(r.id);
  must(await db.from("pickup_reservations").update({ status: "cancelled" }).eq("id", r.id).select("id"));
  toast("取り消しました"); await refreshPickups();
}

// ---------- 日ごとの予約 ----------
// 週のストリップ：月曜はじまりの7日。‹ › で1週間ずつ動かす
const weekStartOf = k => addDays(k, -((parseYMD(k).getDay() + 6) % 7));
function shiftWeek(n) { $("pk-date").value = addDays($("pk-date").value || todayJST(), 7 * n); guard(refreshDay); }
$("pk-prev").onclick = () => shiftWeek(-1);
$("pk-next").onclick = () => shiftWeek(1);
$("pk-today").onclick = () => { $("pk-date").value = todayJST(); guard(refreshDay); };
$("pk-date").onchange = () => { if ($("pk-date").value) guard(refreshDay); };
$("pk-week").addEventListener("click", ev => {
  const b = ev.target.closest("[data-date]"); if (!b) return;
  $("pk-date").value = b.dataset.date; guard(refreshDay);
});

function renderWeek(start, selectedDay, counts, overrides = []) {
  const today = todayJST();
  $("pk-week").innerHTML = Array.from({ length: 7 }, (_, i) => {
    const k = addDays(start, i), dt = parseYMD(k), c = counts.get(k) || { approved: 0, pending: 0 };
    const dots = [...Array(Math.min(c.approved, 3)).fill(""), ...Array(Math.min(c.pending, Math.max(0, 3 - c.approved))).fill("pending")];
    const ov = overrides.filter(o => o.pickup_date === k);
    const ovMode = !ov.length ? "" : ov.some(o => o.is_closed) ? "closed" : "custom";
    const cls = ["day", k === selectedDay ? "selected" : "", k === today ? "today" : "", dt.getDay() === 0 ? "sun" : dt.getDay() === 6 ? "sat" : "",
                 ovMode ? `ov-${ovMode}` : ""].filter(Boolean).join(" ");
    const label = `${dt.getMonth() + 1}月${dt.getDate()}日（${DOW[dt.getDay()]}）　承認 ${c.approved}件・未承認 ${c.pending}件`
      + (ovMode === "closed" ? "・送迎なし" : ovMode === "custom" ? "・時間を調整" : "");
    return `<button type="button" class="${cls}" data-date="${k}" aria-pressed="${k === selectedDay}" aria-label="${label}">
      <span class="dow">${DOW[dt.getDay()]}</span><span class="num">${dt.getDate()}</span>
      <span class="dots">${dots.map(x => `<i class="${x}"></i>`).join("")}</span>
      ${ovMode ? `<span class="ov-mark">${ovMode === "closed" ? "送迎なし" : "時間調整"}</span>` : ""}</button>`;
  }).join("");
}

async function refreshDay() {
  const d = $("pk-date").value || todayJST();
  $("pk-date").value = d;
  const start = weekStartOf(d);
  const [res, grp, wk] = await Promise.all([
    db.from("pickup_reservations").select(RES_SELECT).eq("pickup_date", d).order("pickup_time").order("created_at"),
    fetchGroups([d]),
    // 週のストリップの点（1件＝1つ）に使う件数
    db.from("pickup_reservations").select("pickup_date, status").gte("pickup_date", start).lte("pickup_date", addDays(start, 6)).in("status", ["pending", "approved"]),
  ]);
  const [win, ovs] = await Promise.all([
    db.rpc("pickup_windows", { p_date: d }).then(must),
    db.from("pickup_date_overrides").select("*").gte("pickup_date", start).lte("pickup_date", addDays(start, 6)).order("start_time").then(must),
  ]);
  dayWindows = win; dayOverrides = ovs.filter(o => o.pickup_date === d);
  dayRows = must(res); dayGroups = grp;
  const counts = new Map();
  must(wk).forEach(r => {
    const c = counts.get(r.pickup_date) || { approved: 0, pending: 0 };
    c[r.status === "approved" ? "approved" : "pending"]++;
    counts.set(r.pickup_date, c);
  });
  const pids = dayGroups.map(g => g.id);
  dayProposals = pids.length ? must(await db.from("pickup_proposals").select("*").in("group_id", pids)) : [];
  applyPending(await fetchPending());
  renderWeek(start, d, counts, ovs);
  updatePickupHead();

  const inGroup = id => dayRows.filter(r => r.group_id === id && (r.status === "approved" || r.status === "pending"));
  const waiting = dayRows.filter(r => r.status === "pending" && !r.group_id);
  const closed = dayRows.filter(r => r.status === "rejected" || r.status === "cancelled");
  const riders = dayGroups.reduce((n, g) => n + sumSize(inGroup(g.id)), 0);
  const seats = dayGroups.reduce((n, g) => n + g.max_capacity, 0);
  const waitingIds = new Set(waiting.map(r => r.id));
  [...cpSelected].forEach(id => { if (!waitingIds.has(id)) cpSelected.delete(id); });   // 日付を変えたら選択は外す

  // その日の送迎時間
  const mode = !dayOverrides.length ? "normal" : dayOverrides.some(o => o.is_closed) ? "closed" : "custom";
  const winText = dayWindows.length ? dayWindows.map(w => `${hhmm(w.start_time)}〜${hhmm(w.end_time)}（定員${w.max_capacity}名）`).join("、") : "送迎なし";
  const modeTag = { normal: `通常（${WEEKDAY[parseYMD(d).getDay()]}の設定）`, custom: "この日だけ", closed: "この日は送迎なし" }[mode];
  const note = dayOverrides.find(o => o.note)?.note;
  const hours = `<section class="card hours-card mode-${mode}">
      <div class="hours-main"><span class="kpi-label">この日の送迎時間</span>
        <div class="hours-text"><strong>${esc(winText)}</strong><span class="hours-tag">${modeTag}</span></div>
        ${note ? `<div class="hours-note">📝 ${esc(note)}</div>` : ""}</div>
      <button type="button" class="btn small" id="hours-edit">時間を調整</button></section>`;

  // KPI
  const kpis = `<div class="kpis">
    <section class="card kpi"><span class="kpi-label">便</span>
      <div class="kpi-bottom"><span class="kpi-value">${dayGroups.length}<small>本</small></span></div></section>
    <section class="card kpi"><span class="kpi-label">乗車</span>
      <div class="kpi-bottom"><span class="kpi-value">${riders}<small>名</small></span>${seats ? `<span class="kpi-foot">定員 ${seats}名中</span>` : ""}</div></section>
    <section class="card kpi"><span class="kpi-label">未承認</span>
      <div class="kpi-bottom"><span class="kpi-value">${waiting.length}<small>件</small></span>
        ${waiting.length ? `<span class="kpi-foot warn">● 承認を待っています</span>` : `<span class="kpi-foot ok">✓ すべて処理済み</span>`}</div></section>
  </div>`;

  // 便
  const answerOf = r => { const p = dayProposals.find(x => x.reservation_id === r.id && x.group_id === r.group_id); return p ? effectiveResponse(p) : null; };
  const ANSWER = { waiting: "回答待ち", accepted: "✓ 変更してよい", declined: "✗ できない", expired: "期限切れ（未回答）" };
  const trips = dayGroups.length ? `<div class="trips">${dayGroups.map(g => {
    const members = inGroup(g.id);
    const summary = g.status === "proposing" ? proposalSummary({ ...g, pickup_reservations: members }, dayProposals.filter(p => p.group_id === g.id)) : null;
    const load = sumSize(members);
    const pct = Math.min(100, Math.round(load / g.max_capacity * 100));
    return `<article class="trip ${g.status}" data-gid="${g.id}">
      <div class="trip-top">
        <span class="trip-time">${hhmm(g.approved_time)}</span>
        <span class="trip-arrive">発 → ${tripEnd(g)} 着</span>
        ${pickupBadge(g.status === "proposing" ? "proposing" : "approved")}
        <div class="trip-load"><span>乗車 <strong>${load}/${g.max_capacity}</strong></span>
          <span class="bar-track" role="img" aria-label="定員 ${g.max_capacity}名中 ${load}名"><span class="bar-fill" style="width:${pct}%"></span></span></div>
      </div>
      ${summary ? `<p class="trip-note">相乗りの打診中：${summary.text}${summary.needsAction ? ` <span class="urgent">要対応</span>` : ""}</p>` : ""}
      <ul class="riders">${members.map(r => riderHTML(r, {
        sub: `希望 ${hhmm(r.pickup_time)}${sizeText(r)}`,
        extra: r.status === "pending" && answerOf(r) ? ` <span class="answer ${answerOf(r)}">${ANSWER[answerOf(r)]}</span>` : "",
        actions: `${callBtn(r)}<button type="button" class="btn small danger" data-act="cancel-res">取り消す</button>`,
      })).join("")}</ul>
      ${g.status === "proposing" ? `<div class="trip-actions">
        <button type="button" class="btn small primary" data-gact="confirm_all" title="電話などで全員に確認できたとき">電話で確認済みとして確定</button>
        ${summary?.needsAction ? `<button type="button" class="btn small" data-gact="drop_declined">辞退・未回答の人を外す</button>` : ""}
        <button type="button" class="btn small danger" data-gact="cancel">調整をやめる</button></div>` : ""}
    </article>`;
  }).join("")}</div>` : `<p class="empty-note">この日の便はまだありません。<br>未承認の予約を承認すると、便ができます。</p>`;

  // 未承認
  const unapproved = waiting.length ? `
      <div class="cp-bar"${cpSelected.size ? "" : " hidden"}><span class="count">選択中 <strong>${cpSelected.size}</strong>件</span>
        <button type="button" class="btn small primary" id="cp-open"${cpSelected.size >= 2 ? "" : " disabled"}>相乗り調整</button>
        <span class="hint" style="margin:0">2件以上選ぶと、共通の時刻を提案できます</span></div>
      <ul class="riders">${waiting.map(r => pendingRiderHTML(r, dayGroups, true)).join("")}</ul>`
    : emptyOk("未承認の予約はありません");
  const closedHTML = closed.length ? `<details class="closed"><summary>却下・キャンセル（${closed.length}件）</summary><ul>${closed.map(r =>
    `<li>${hhmm(r.pickup_time)}　${esc(nameOf(r))}　${pickupBadge(r.status)}${r.reject_reason ? `　<small>${esc(r.reject_reason)}</small>` : ""}</li>`).join("")}</ul></details>` : "";

  $("pk-day-body").innerHTML = `${hours}${kpis}
    <div class="lower">
      <section class="card"><div class="card-head"><h2>便</h2><span class="count">${dayGroups.length}本</span></div>${trips}</section>
      <section class="card"><div class="card-head"><h2>未承認</h2>${waiting.length ? `<span class="count">${waiting.length}件</span>` : ""}</div>${unapproved}${closedHTML}</section>
    </div>`;
}
$("pk-day-body").addEventListener("click", ev => {
  if (ev.target.closest("#cp-open")) { openCarpoolDialog(); return; }
  if (ev.target.closest("#hours-edit")) { guard(openHoursDialog); return; }
  const ga = ev.target.closest("[data-gact]");
  if (ga) { guard(() => resolveGroup(ga.closest("[data-gid]").dataset.gid, ga.dataset.gact)); return; }
  onReservationAction(ev, dayRows, dayGroups);
});
$("pk-day-body").addEventListener("change", ev => {
  if (!ev.target.classList.contains("cp-check")) return;
  const id = ev.target.closest("[data-id]").dataset.id;
  if (ev.target.checked) cpSelected.add(id); else cpSelected.delete(id);
  guard(refreshDay);
});

// ---------- その日の送迎時間の調整 ----------
let hoursTrip = 15;
async function openHoursDialog() {
  const d = $("pk-date").value || todayJST();
  const dow = parseYMD(d).getDay();
  const [weekly, ps] = await Promise.all([
    db.from("pickup_availability").select("*").eq("day_of_week", dow).eq("is_active", true).order("start_time").then(must),
    db.from("pickup_settings").select("default_capacity, trip_minutes").eq("id", 1).single().then(must),
  ]);
  hoursTrip = ps.trip_minutes;
  const mode = !dayOverrides.length ? "normal" : dayOverrides.some(o => o.is_closed) ? "closed" : "custom";
  $("hr-date").textContent = `${fmtDay(d)} の送迎時間`;
  $("hr-normal").textContent = weekly.length ? `${DOW[dow]}曜日：${weekly.map(w => `${hhmm(w.start_time)}〜${hhmm(w.end_time)}`).join("、")}` : `${DOW[dow]}曜日は送迎なし`;
  document.querySelectorAll('input[name="hr-mode"]').forEach(r => { r.checked = r.value === mode; });
  // 「この日だけ」の初期値：今の調整、無ければ曜日の設定
  const base = mode === "custom" ? dayOverrides.filter(o => !o.is_closed) : weekly;
  $("hr-windows").innerHTML = "";
  (base.length ? base : [{ start_time: "16:00", end_time: "21:00", max_capacity: ps.default_capacity }])
    .forEach(w => addHoursRow(hhmm(w.start_time), hhmm(w.end_time), w.max_capacity));
  $("hr-note").value = dayOverrides.find(o => o.note)?.note || "";
  updateHoursMode();
  $("pk-hours-dlg").showModal();
}
function addHoursRow(start = "", end = "", cap = 3) {
  $("hr-windows").insertAdjacentHTML("beforeend", `<div class="hr-row">
    <label>開始<input type="time" class="hr-start" value="${esc(start)}" required></label>
    <label>終了<input type="time" class="hr-end" value="${esc(end)}" required></label>
    <label>定員<input type="number" class="hr-cap" min="1" max="8" value="${esc(cap)}" required></label>
    <button type="button" class="btn small danger hr-del" aria-label="この時間帯を消す">削除</button></div>`);
}
function updateHoursMode() {
  const mode = document.querySelector('input[name="hr-mode"]:checked')?.value;
  $("hr-custom").hidden = mode !== "custom";
  $("hr-windows").querySelectorAll("input").forEach(i => { i.disabled = mode !== "custom"; });
}
$("hours-form").addEventListener("change", e => { if (e.target.name === "hr-mode") updateHoursMode(); });
$("hr-add").onclick = () => addHoursRow("", "", 3);
$("hr-windows").addEventListener("click", e => {
  const b = e.target.closest(".hr-del"); if (!b) return;
  if ($("hr-windows").children.length > 1) b.closest(".hr-row").remove();
  else toast("時間帯を1つ以上残すか、「この日は送迎なし」を選んでください", true);
});
$("hr-cancel").onclick = () => $("pk-hours-dlg").close();
$("hours-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const d = $("pk-date").value || todayJST();
    const mode = document.querySelector('input[name="hr-mode"]:checked')?.value;
    if (!mode) throw new Error("この日の送迎を選んでください。");
    const windows = mode !== "custom" ? [] : [...$("hr-windows").querySelectorAll(".hr-row")].map(r => ({
      start: r.querySelector(".hr-start").value, end: r.querySelector(".hr-end").value, capacity: +r.querySelector(".hr-cap").value,
    }));
    if (mode === "custom") {
      if (windows.some(w => !w.start || !w.end)) throw new Error("開始時刻と終了時刻を入力してください。");
      if (windows.some(w => w.end <= w.start)) throw new Error("終了時刻は開始時刻より後にしてください。");
    }
    // 時間外になる予約（取り消しはしない。お知らせだけ）
    let outside = [];
    if (mode !== "normal") {
      outside = dayRows.filter(r => (r.status === "pending" || r.status === "approved") && !windows.some(w => {
        const t = toMin(hhmm(r.approved_time || r.pickup_time));
        return t >= toMin(w.start) && t + hoursTrip <= toMin(w.end);
      }));
    }
    const label = { normal: "通常どおり（曜日の設定）", custom: `この日だけ ${windows.map(w => `${w.start}〜${w.end}（定員${w.capacity}名）`).join("、")}`, closed: "送迎なし" }[mode];
    const warn = outside.length ? `\n\n⚠ 次の予約は時間外になります（予約は残ります。必要なら生徒に連絡して、取り消しや時刻の変更をしてください）\n${
      outside.map(r => `・${hhmm(r.approved_time || r.pickup_time)} ${nameOf(r)}（${PICKUP_STATUS[pickupStatusOf(r)]}）`).join("\n")}` : "";
    if (!confirm(`${fmtDay(d)} の送迎を「${label}」にします。${warn}\n\nよろしいですか？`)) return;
    must(await db.rpc("admin_set_pickup_day", { p_date: d, p_mode: mode, p_windows: windows, p_note: $("hr-note").value.trim() }));
    $("pk-hours-dlg").close();
    toast(`${fmtDay(d)} の送迎時間を保存しました`);
    await refreshDay();
  });
});

// ---------- 相乗り調整 ----------
async function openCarpoolDialog() {
  cpRows = dayRows.filter(r => cpSelected.has(r.id));
  if (cpRows.length < 2) return;
  const d = cpRows[0].pickup_date;
  const [av, ps] = await Promise.all([
    db.rpc("pickup_windows", { p_date: d }).then(must),
    db.from("pickup_settings").select("*").eq("id", 1).single().then(must),
  ]);
  const times = cpRows.map(r => hhmm(r.pickup_time));
  const earliest = times.reduce((a, b) => (a < b ? a : b));
  // 希望時刻を含む時間帯を、出発できる範囲にする（最終便＝終了 − 所要時間）
  const w = av.find(a => hhmm(a.start_time) <= earliest && earliest < hhmm(a.end_time));
  const win = w ? [hhmm(w.start_time), fromMin(toMin(hhmm(w.end_time)) - ps.trip_minutes)] : null;
  const cap = w ? w.max_capacity : ps.default_capacity;
  const busy = dayGroups.map(g => [hhmm(g.approved_time), tripEnd(g)]);
  const sg = suggestTime(times, { tolerance: ps.tolerance_minutes, step: 5, window: win, busy, trip: ps.trip_minutes });

  const total = sumSize(cpRows);
  $("cp-summary").textContent = `${fmtDay(d)}　${cpRows.length}件・合計${total}名（定員 ${cap}名）${total > cap ? "　⚠ 定員を超えています" : ""}`;
  $("cp-members").innerHTML = `<thead><tr><th>生徒</th><th>希望時刻</th><th>人数</th><th>電話番号</th></tr></thead><tbody>${cpRows.map(r =>
    `<tr><td><strong>${esc(nameOf(r))}</strong>${esc(gradeOf(r))}</td><td>${hhmm(r.pickup_time)}</td><td>${sizeOf(r)}名</td><td>${esc(r.students?.phone || "")}</td></tr>`).join("")}</tbody>`;
  $("cp-suggest").innerHTML = sg.candidates.length
    ? `<p><strong>共通時刻の提案</strong>（希望から ±${ps.tolerance_minutes}分・ほかの便と重ならない時刻）：${sg.from}〜${sg.to}</p>
       <div class="cp-cands">${sg.candidates.map(c => `<button type="button" class="slot-chip${c === sg.best ? " best" : ""}" data-t="${c}">${c}${c === sg.best ? "（おすすめ）" : ""}</button>`).join("")}</div>`
    : `<p class="msg">希望から ±${ps.tolerance_minutes}分以内に、ほかの便と重ならない共通の時刻がありません。時刻を直接入力してください。</p>`;
  $("cp-time").value = sg.best || times[0];
  $("cp-send").disabled = total > cap;
  $("cp-msg").textContent = "";
  $("pk-carpool-dlg").showModal();
}
$("cp-suggest").addEventListener("click", ev => { const b = ev.target.closest("[data-t]"); if (b) $("cp-time").value = b.dataset.t; });
$("cp-cancel").onclick = () => $("pk-carpool-dlg").close();
$("cp-send").onclick = () => guard(async () => {
  const t = $("cp-time").value;
  if (!t) { $("cp-msg").textContent = "出発時刻を入力してください。"; return; }
  const asked = cpRows.filter(r => hhmm(r.pickup_time) !== t);
  if (!confirm(`${fmtDay(cpRows[0].pickup_date)} ${t} 発で相乗りにします。\n\n打診する人：${asked.map(nameOf).join("、") || "なし（全員が希望どおり）"}\n\nよろしいですか？`)) return;
  try {
    await sendProposal(cpRows, t, null);
    $("pk-carpool-dlg").close();
    cpSelected.clear();
  } catch (e) { $("cp-msg").textContent = e.message; }
});

// 打診を送る（開発中は回答用のリンクを表示。本番は LINE で自動送信する）
async function sendProposal(rows, time, groupId) {
  rows.forEach(r => localChanges.add(r.id));
  const res = must(await db.rpc("admin_propose_carpool", { p_reservation_ids: rows.map(r => r.id), p_time: time, p_group: groupId }));
  rows.forEach(r => knownPending.delete(r.id));
  const links = res.filter(x => x.token).map(x => ({ r: rows.find(r => r.id === x.reservation_id), url: `${location.origin}/pickup-respond.html?t=${x.token}` }));
  await refreshPickups();
  if (!links.length) { toast("全員が希望どおりの時刻なので、そのまま確定しました"); return; }
  $("lk-hint").textContent = SUPABASE_ENV === "dev"
    ? "開発中は、このリンクを開いて回答を試せます（本番では LINE で自動送信します）。リンクは今だけ表示されます。"
    : "LINE での自動送信は準備中です。このリンクを生徒に送ってください。リンクは今だけ表示されます。";
  $("lk-list").innerHTML = links.map(l => `<div class="lk-item"><strong>${esc(nameOf(l.r))}</strong>
    <input type="text" readonly value="${esc(l.url)}" aria-label="${esc(nameOf(l.r))}の回答リンク">
    <span class="actions"><button type="button" class="btn small" data-copy>コピー</button><a class="btn small" href="${esc(l.url)}" target="_blank" rel="noopener">開く</a></span></div>`).join("");
  $("pk-links-dlg").showModal();
}
$("lk-list").addEventListener("click", ev => {
  const b = ev.target.closest("[data-copy]"); if (!b) return;
  const input = b.closest(".lk-item").querySelector("input");
  navigator.clipboard.writeText(input.value).then(() => toast("コピーしました"), () => { input.select(); toast("手動でコピーしてください", true); });
});
$("lk-close").onclick = () => $("pk-links-dlg").close();

async function resolveGroup(gid, action) {
  const g = dayGroups.find(x => x.id === gid);
  const label = { confirm_all: "全員に確認できたものとして、この便を確定", drop_declined: "「できない」と答えた人・未回答の人を便から外し（その人は未承認に戻ります）、残りの人で確定", cancel: "相乗りの調整をやめ、全員を未承認に戻" }[action];
  if (!confirm(`${fmtDay(g.pickup_date)} ${hhmm(g.approved_time)} 発の便を、${label}します。\n\nよろしいですか？`)) return;
  dayRows.filter(r => r.group_id === gid).forEach(r => localChanges.add(r.id));
  const st = must(await db.rpc("admin_resolve_group", { p_group: gid, p_action: action }));
  toast(st === "confirmed" ? "確定しました" : st === "cancelled" ? "調整をやめました" : "便から外しました（まだ全員の承認がそろっていません）");
  await refreshPickups();
}

// ---------- 通知 ----------
// 予約が入ったら：画面の中央に通知を出し、ボタンを押すまで音を繰り返し鳴らし、タブ名を点滅させる。
// さらに、ブラウザの通知（クリックするまで消えない）も出す。
const REPEAT_MS = 8000;              // 音を鳴らし直す間隔
const REPEAT_LIMIT_MS = 10 * 60000;  // 最長10分で鳴らすのをやめる（通知は残る）
let audioCtx = null;
let alarmTimer = null, blinkTimer = null, alarmStarted = 0;
let alertItems = [];                 // 通知中の項目 { title, body, view, date }
let lastAlertView = { view: "pending", date: null };

// 既定はオン（明示的にオフにしたときだけ鳴らさない）
const notifyOn = () => { try { return localStorage.getItem(NOTIFY_KEY) !== "0"; } catch { return true; } };
function setNotifyOn(on) { try { localStorage.setItem(NOTIFY_KEY, on ? "1" : "0"); } catch { /* 保存できなくても続ける */ } updateNotifyButton(); }
function updateNotifyButton() {
  const on = notifyOn();
  $("notify-toggle").textContent = on ? "🔔 音オン" : "🔕 音オフ";
  $("notify-toggle").setAttribute("aria-pressed", String(on));
  $("notify-toggle").title = on ? "予約が入ったら音を鳴らします（クリックでオフ）" : "クリックすると、予約が入ったときに音を鳴らします";
  updateUnlockBanner();
}
const audioReady = () => audioCtx?.state === "running";
function updateUnlockBanner() { $("sound-unlock").hidden = !notifyOn() || audioReady(); }

// ブラウザは、画面を1回クリックするまで音を出させてくれない。クリックされたら音とブラウザの通知を使えるようにする
function unlockAudio() {
  try {
    audioCtx ??= new (window.AudioContext || window.webkitAudioContext)();
    if (audioCtx.state === "suspended") audioCtx.resume().then(updateUnlockBanner);
  } catch (e) { console.warn("音を使えません", e); }
  updateUnlockBanner();
}
document.addEventListener("pointerdown", unlockAudio, { passive: true });
document.addEventListener("keydown", unlockAudio);
$("sound-unlock").onclick = async () => {
  unlockAudio();
  setTimeout(chime, 100);   // 試しに1回鳴らす
  if ("Notification" in window && Notification.permission === "default") await Notification.requestPermission();
  toast("音の通知を使えるようにしました。管理画面は開いたままにしてください");
};
$("notify-toggle").onclick = async () => {
  if (notifyOn()) { setNotifyOn(false); stopAlarm(); toast("音をオフにしました（画面の通知は出ます）"); return; }
  setNotifyOn(true); unlockAudio(); setTimeout(chime, 100);
  if ("Notification" in window && Notification.permission === "default") await Notification.requestPermission();
  toast("音をオンにしました");
};

// ピンポーン×2（はっきり聞こえるよう、三角波で大きめに）
function chime() {
  if (!notifyOn() || !audioCtx) return;
  try {
    if (audioCtx.state === "suspended") audioCtx.resume();
    const t0 = audioCtx.currentTime + 0.05;
    const master = audioCtx.createGain();
    master.gain.value = 0.9;
    master.connect(audioCtx.destination);
    [[1319, 0], [988, 0.35], [1319, 0.9], [988, 1.25]].forEach(([f, at]) => {
      const o = audioCtx.createOscillator(), g = audioCtx.createGain();
      o.type = "triangle"; o.frequency.value = f;
      g.gain.setValueAtTime(0.0001, t0 + at);
      g.gain.exponentialRampToValueAtTime(1, t0 + at + 0.02);
      g.gain.exponentialRampToValueAtTime(0.0001, t0 + at + 0.6);
      o.connect(g).connect(master);
      o.start(t0 + at); o.stop(t0 + at + 0.65);
    });
  } catch (e) { console.warn("音を鳴らせませんでした", e); }
}

function startAlarm() {
  chime();
  if (alarmTimer) return;
  alarmStarted = Date.now();
  alarmTimer = setInterval(() => { if (Date.now() - alarmStarted > REPEAT_LIMIT_MS) { clearInterval(alarmTimer); alarmTimer = null; } else chime(); }, REPEAT_MS);
  let on = false;
  blinkTimer = setInterval(() => { on = !on; document.title = on ? "🔔 送迎予約が入りました！" : baseTitle(); }, 1000);
}
function stopAlarm() {
  clearInterval(alarmTimer); alarmTimer = null;
  clearInterval(blinkTimer); blinkTimer = null;
  document.title = baseTitle();
}
const baseTitle = () => { const n = pendingRows.length; return (n ? `(${n}) ` : "") + "碩学館 管理画面"; };

function renderAlert() {
  const kinds = new Set(alertItems.map(i => i.kind));
  $("pk-alert-title").textContent = kinds.size === 1 && kinds.has("new")
    ? `🚗 新しい送迎予約が入りました${alertItems.length > 1 ? `（${alertItems.length}件）` : ""}`
    : alertItems.length === 1 ? alertItems[0].title : `🔔 お知らせ（${alertItems.length}件）`;
  $("pk-alert-list").innerHTML = alertItems.map(i => `<li class="${i.kind}"><strong>${esc(i.title)}</strong><br>${esc(i.body)}</li>`).join("");
}
function closeAlert() {
  stopAlarm();
  alertItems = [];
  if ($("pk-alert").open) $("pk-alert").close();
}
$("pk-alert-close").onclick = closeAlert;
$("pk-alert-open").onclick = () => { const v = lastAlertView; closeAlert(); v.open ? v.open() : openPickupsTab(v.view, v.date); };
$("pk-alert").addEventListener("cancel", () => stopAlarm());   // Esc で閉じたとき

// open を渡すと、「開く」を押したときの移動先を変えられる（欠席・振替の通知など）
function notify({ kind, title, body, view, date, tag, open }) {
  alertItems.unshift({ kind, title, body });
  alertItems = alertItems.slice(0, 8);
  lastAlertView = { view, date, open };
  renderAlert();
  if (!$("pk-alert").open) $("pk-alert").showModal();
  startAlarm();
  if ("Notification" in window && Notification.permission === "granted") {
    try {
      const n = new Notification(title, { body, tag, requireInteraction: true });
      n.onclick = () => { window.focus(); closeAlert(); open ? open() : openPickupsTab(view, date); n.close(); };
    } catch (e) { console.warn("ブラウザの通知を出せませんでした", e); }
  }
}

async function studentName(id) {
  const s = must(await db.from("students").select("name").eq("id", id).maybeSingle());
  return s ? `${s.name}さん` : "生徒";
}

async function onNewPending(r) {
  if (knownPending.has(r.id)) return;
  knownPending.add(r.id);
  const who = r.students ? nameOf(r) : await studentName(r.student_id);
  notify({ kind: "new", title: "🚗 新しい送迎予約", body: `${who}　${fmtDay(r.pickup_date)} ${hhmm(r.pickup_time)} 発${sizeText(r)}`, view: "pending", tag: r.id });
}

async function onReservationUpdate(r) {
  if (localChanges.has(r.id)) { localChanges.delete(r.id); return refreshIfVisible(); }
  if (r.status === "cancelled") {
    notify({ kind: "cancel", title: "↩ 送迎予約の取り消し", body: `${await studentName(r.student_id)}　${fmtDay(r.pickup_date)} ${hhmm(r.approved_time || r.pickup_time)} 発`, view: "day", date: r.pickup_date, tag: r.id + ":c" });
  } else if (r.status === "rejected" && r.reject_reason === "期限切れ") {
    notify({ kind: "expired", title: "⌛ 承認されないまま時刻を過ぎました", body: `${await studentName(r.student_id)}　${fmtDay(r.pickup_date)} ${hhmm(r.pickup_time)} 発`, view: "day", date: r.pickup_date, tag: r.id + ":e" });
  }
  knownPending.delete(r.id);
  await refreshIfVisible();
}

async function onProposalUpdate(p) {
  if (p.response !== "accepted" && p.response !== "declined") return;
  const r = must(await db.from("pickup_reservations").select(RES_SELECT).eq("id", p.reservation_id).maybeSingle());
  if (!r || localChanges.has(r.id)) return;
  notify({ kind: p.response === "accepted" ? "new" : "cancel", title: p.response === "accepted" ? "✓ 相乗りの打診に承認" : "✗ 相乗りの打診を辞退",
           body: `${nameOf(r)}　${fmtDay(r.pickup_date)} ${hhmm(p.proposed_time)} 発`, view: "day", date: r.pickup_date, tag: p.id });
  await refreshIfVisible();
}

async function refreshIfVisible() {
  if (!$("tab-pickups").hidden) await refreshPickups();
  else applyPending(await fetchPending());
}

function subscribeRealtime() {
  const state = $("rt-state");
  pkChannel = db.channel("pickup-admin")
    .on("postgres_changes", { event: "INSERT", schema: "public", table: "pickup_reservations" },
        p => guard(async () => { if (p.new.status === "pending") { await onNewPending(p.new); await refreshIfVisible(); } }))
    .on("postgres_changes", { event: "UPDATE", schema: "public", table: "pickup_reservations" }, p => guard(() => onReservationUpdate(p.new)))
    .on("postgres_changes", { event: "UPDATE", schema: "public", table: "pickup_proposals" }, p => guard(() => onProposalUpdate(p.new)))
    .subscribe(status => {
      const ok = status === "SUBSCRIBED";
      state.textContent = ok ? "リアルタイム受信中" : "15秒ごとに確認中";   // 丸い印は CSS で付ける
      state.classList.toggle("ok", ok);
    });
}

// Realtime が切れていても、15秒ごとに新しい未承認を拾う（通知済みのものは二重に出さない）
async function pollPending() {
  const rows = await fetchPending();
  for (const r of rows) if (!knownPending.has(r.id)) await onNewPending(r);
  const ids = new Set(rows.map(r => r.id));
  [...knownPending].forEach(id => { if (!ids.has(id)) knownPending.delete(id); });
  applyPending(rows);
}
