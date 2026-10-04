"use strict";
// 管理画面：欠席・振替（承認待ち・日ごと・生徒ごと・設定）と、欠席の連絡・振替の申請の通知。
// admin-reservations.js のあと（通知の notify、乗客の行の riderHTML、studentName などを使う）に読み込む。

const AB_VIEWS = { pending: "承認待ち", day: "日ごと", student: "生徒ごと", settings: "設定" };
const CLASS_TYPES = ["高1授業", "高2授業", "高3授業"];
const AB_REQ_LABEL = { pending: "申請中", approved: "承認", rejected: "却下", cancelled: "取り消し" };
const AB_REQ_BADGE = { pending: "pending", approved: "approved", rejected: "rejected", cancelled: "cancelled" };
const AB_CREDIT_LABEL = { available: "使える", expired: "期限切れ", reserved: "申請中", used: "使用済み", revoked: "取り消し" };
const AB_CREDIT_BADGE = { available: "approved", expired: "cancelled", reserved: "proposing", used: "rejected", revoked: "rejected" };
const AB_SELECT = "*, students(name, grade, phone)";

let abView = "pending";
let abRows = [];              // いま表示している申請・欠席（操作のときに探す）
let abRejecting = null;
let abStudents = [];
let abChannel = null, abPoll = null, abStarted = false;
const abKnown = new Set();    // 通知済み（または起動時からある）欠席・申請
const abLocal = new Set();    // この画面で操作した申請（自分の操作は通知しない）

const classLabelA = t => String(t).replace("授業", "の授業");
const classTime = r => (r.start_time ? `${hhmm(r.start_time)}〜${hhmm(r.end_time)}` : "");
const creditStatus = c => (c.status === "available" && c.expires_on < todayJST() ? "expired" : c.status);

// ---------- 起動・通知 ----------
async function initAbsenceAdmin() {
  if (abStarted) return;
  abStarted = true;
  $("ab-date").value = todayJST();
  const [reqs, abs] = await Promise.all([fetchAbPending(), fetchRecentAbsences()]);
  reqs.forEach(r => abKnown.add("m:" + r.id));
  abs.forEach(a => abKnown.add("a:" + a.id));
  setAbBadge(reqs.length);
  abChannel = db.channel("absence-admin")
    .on("postgres_changes", { event: "INSERT", schema: "public", table: "class_absences" }, p => guard(() => onNewAbsence(p.new)))
    .on("postgres_changes", { event: "INSERT", schema: "public", table: "makeup_requests" }, p => guard(() => onNewMakeup(p.new)))
    .on("postgres_changes", { event: "UPDATE", schema: "public", table: "makeup_requests" }, p => guard(() => onMakeupUpdate(p.new)))
    .on("postgres_changes", { event: "UPDATE", schema: "public", table: "class_absences" }, p => guard(() => onAbsenceUpdate(p.new)))
    .subscribe();
  abPoll = setInterval(() => guard(pollAbsence), 15000);
}
if (!$("app").hidden) guard(initAbsenceAdmin);
db?.auth.onAuthStateChange(ev => {
  if (ev !== "SIGNED_OUT") return;
  abStarted = false;
  clearInterval(abPoll);
  if (abChannel) { db.removeChannel(abChannel); abChannel = null; }
  abKnown.clear();
  setAbBadge(0);
});

async function fetchAbPending() {
  return must(await db.from("makeup_requests").select(AB_SELECT).eq("status", "pending").gte("class_date", todayJST())
    .order("class_date").order("start_time"));
}
async function fetchRecentAbsences() {
  return must(await db.from("class_absences").select("id, student_id, class_date, class_type, created_at")
    .eq("status", "registered").gte("created_at", new Date(Date.now() - 864e5).toISOString()));
}
function setAbBadge(n) {
  $("ab-badge").hidden = !n; $("ab-badge").textContent = n;
  $("ab-count").textContent = n ? `(${n})` : "";
}
const openAbsenceTab = (view, date) => () => {
  document.querySelector('#tabs button[data-tab="absence"]').click();
  if (date) $("ab-date").value = date;
  setAbView(view);
  guard(refreshAbsenceAdmin);
};

async function onNewAbsence(a) {
  if (abKnown.has("a:" + a.id) || a.status !== "registered") return;
  abKnown.add("a:" + a.id);
  notify({ kind: "cancel", title: "📝 欠席の連絡", body: `${await studentName(a.student_id)}　${fmtDay(a.class_date)} ${classLabelA(a.class_type)}`,
           tag: "a:" + a.id, open: openAbsenceTab("day", a.class_date) });
  await refreshAbsenceIfVisible();
}
async function onNewMakeup(r) {
  if (abKnown.has("m:" + r.id) || r.status !== "pending") return;
  abKnown.add("m:" + r.id);
  notify({ kind: "new", title: "🔁 振替の申請", body: `${await studentName(r.student_id)}　${fmtDay(r.class_date)} ${classLabelA(r.class_type)}`,
           tag: "m:" + r.id, open: openAbsenceTab("pending") });
  await refreshAbsenceIfVisible();
}
async function onMakeupUpdate(r) {
  if (abLocal.has(r.id)) { abLocal.delete(r.id); return refreshAbsenceIfVisible(); }
  if (r.status === "cancelled") {
    notify({ kind: "cancel", title: "↩ 振替の申請の取り消し", body: `${await studentName(r.student_id)}　${fmtDay(r.class_date)} ${classLabelA(r.class_type)}`,
             tag: "mc:" + r.id, open: openAbsenceTab("day", r.class_date) });
  }
  await refreshAbsenceIfVisible();
}
async function onAbsenceUpdate(a) {
  if (a.status === "cancelled") {
    notify({ kind: "expired", title: "↩ 欠席の連絡の取り消し", body: `${await studentName(a.student_id)}　${fmtDay(a.class_date)} ${classLabelA(a.class_type)}`,
             tag: "ac:" + a.id, open: openAbsenceTab("day", a.class_date) });
  }
  await refreshAbsenceIfVisible();
}
// Realtime が切れていても、15秒ごとに新しい申請・欠席を拾う
async function pollAbsence() {
  const [reqs, abs] = await Promise.all([fetchAbPending(), fetchRecentAbsences()]);
  for (const r of reqs) await onNewMakeup(r);
  for (const a of abs) await onNewAbsence({ ...a, status: "registered" });
  setAbBadge(reqs.length);
}
async function refreshAbsenceIfVisible() {
  if (!$("tab-absence").hidden) await refreshAbsenceAdmin();
  else setAbBadge((await fetchAbPending()).length);
}

// ---------- タブ・表示の切り替え ----------
document.querySelectorAll("#tabs button").forEach(b => b.addEventListener("click", () => {
  if (b.dataset.tab === "absence") guard(refreshAbsenceAdmin);
}));
document.querySelectorAll("#tab-absence .seg button").forEach(b => b.onclick = () => { setAbView(b.dataset.abview); guard(refreshAbsenceAdmin); });
$("ab-refresh-admin").onclick = () => guard(refreshAbsenceAdmin);
function setAbView(v) {
  abView = v;
  document.querySelectorAll("#tab-absence .seg button").forEach(b => {
    const on = b.dataset.abview === v;
    b.classList.toggle("active", on); b.setAttribute("aria-pressed", String(on));
  });
  Object.keys(AB_VIEWS).forEach(k => { $("abv-" + k).hidden = k !== v; });
  $("ab-crumb").textContent = AB_VIEWS[v];
  if (v !== "day") $("ab-title").textContent = AB_VIEWS[v];
}
const refreshAbsenceAdmin = () => ({ pending: abRefreshPending, day: abRefreshDay, student: abRefreshStudent, settings: abRefreshSettings })[abView]();

// ---------- 承認待ち ----------
async function abRefreshPending() {
  const [reqs, abs] = await Promise.all([
    fetchAbPending(),
    db.from("class_absences").select(AB_SELECT).eq("status", "registered").gte("class_date", todayJST()).order("class_date").order("start_time").then(must),
  ]);
  abRows = [...reqs, ...abs];
  setAbBadge(reqs.length);
  $("ab-title").innerHTML = `承認待ち<small>${reqs.length}件</small>`;
  $("abv-pending").innerHTML = `
    <section class="card"><div class="card-head"><h2>振替の申請</h2><span class="count">${reqs.length}件</span></div>
      ${reqs.length ? `<ul class="riders">${reqs.map(r => riderHTML(r, {
        sub: `${fmtDay(r.class_date)} ${classLabelA(r.class_type)} ${classTime(r)} · 受付 ${receivedAt(r)}`,
        actions: `<button type="button" class="btn small primary" data-abact="approve">承認</button>
                  <button type="button" class="btn small danger" data-abact="reject">却下</button>`,
      })).join("")}</ul>` : emptyOk("承認待ちの振替の申請はありません")}</section>
    <section class="card adjusting"><div class="card-head"><h2>今後の欠席の連絡</h2><span class="count">${abs.length}件</span></div>
      ${abs.length ? `<ul class="riders">${abs.map(a => riderHTML({ ...a, notes: a.reason }, {
        sub: `${fmtDay(a.class_date)} ${classLabelA(a.class_type)} ${classTime(a)} · 受付 ${receivedAt(a)}`,
        actions: `<button type="button" class="btn small" data-abact="open-day" data-date="${esc(a.class_date)}">日ごとで見る</button>`,
      })).join("")}</ul>` : `<p class="empty-note">今後の欠席の連絡はありません。</p>`}</section>`;
}

// ---------- 日ごと ----------
function abShiftDay(n) { $("ab-date").value = addDays($("ab-date").value || todayJST(), n); guard(abRefreshDay); }
$("ab-prev").onclick = () => abShiftDay(-1);
$("ab-next").onclick = () => abShiftDay(1);
$("ab-today").onclick = () => { $("ab-date").value = todayJST(); guard(abRefreshDay); };
$("ab-date").onchange = () => { if ($("ab-date").value) guard(abRefreshDay); };

async function abRefreshDay() {
  const d = $("ab-date").value || todayJST();
  $("ab-date").value = d;
  const [evs, abs, reqs, st] = await Promise.all([
    db.from("events").select("*").eq("event_date", d).in("type", CLASS_TYPES).order("start_time").then(must),
    db.from("class_absences").select(AB_SELECT).eq("class_date", d).eq("status", "registered").then(must),
    db.from("makeup_requests").select(AB_SELECT).eq("class_date", d).in("status", ["pending", "approved"]).order("created_at").then(must),
    db.from("makeup_settings").select("*").eq("id", 1).single().then(must),
  ]);
  abRows = [...abs, ...reqs];
  const dt = parseYMD(d);
  $("ab-title").innerHTML = `${dt.getMonth() + 1}月${dt.getDate()}日<small>${WEEKDAY[dt.getDay()]}</small>`;
  // 授業（予定から消えていても、欠席・振替の記録があれば出す）
  const types = [...new Set([...evs.map(e => e.type), ...abs.map(a => a.class_type), ...reqs.map(r => r.class_type)])].sort();
  if (!types.length) { $("abv-day-body").innerHTML = `<section class="card"><p class="empty-note">この日の授業はありません。</p></section>`; return; }
  $("abv-day-body").innerHTML = `<div class="trips">${types.map(t => {
    const e = evs.find(x => x.type === t), a = abs.filter(x => x.class_type === t), r = reqs.filter(x => x.class_type === t);
    const time = e ? classTime(e) : classTime(a[0] || r[0] || {});
    return `<section class="card class-card">
      <div class="card-head"><h2>${esc(classLabelA(t))} <span class="trip-arrive">${esc(time)}</span>${e && !e.is_published ? ` <span class="pst pst-rejected">下書き</span>` : ""}${!e ? ` <span class="pst pst-cancelled">予定にありません</span>` : ""}</h2>
        <span class="count">欠席 ${a.length}名・振替 ${r.length}/${st.makeup_capacity}名</span></div>
      <div class="class-cols">
        <div><h3>欠席</h3>${a.length ? `<ul class="riders">${a.map(x => riderHTML({ ...x, notes: x.reason }, { sub: `受付 ${receivedAt(x)}` })).join("")}</ul>` : `<p class="empty-note">なし</p>`}</div>
        <div><h3>振替で来る</h3>${r.length ? `<ul class="riders">${r.map(x => riderHTML(x, {
          sub: `受付 ${receivedAt(x)}`, extra: ` <span class="pst pst-${AB_REQ_BADGE[x.status]}">${AB_REQ_LABEL[x.status]}</span>`,
          actions: x.status === "pending"
            ? `<button type="button" class="btn small primary" data-abact="approve">承認</button><button type="button" class="btn small danger" data-abact="reject">却下</button>`
            : `<button type="button" class="btn small danger" data-abact="cancel-makeup">取り消す</button>`,
        })).join("")}</ul>` : `<p class="empty-note">なし</p>`}</div>
      </div></section>`;
  }).join("")}</div>`;
}

// ---------- 生徒ごと ----------
$("ab-student").onchange = () => guard(abRefreshStudent);
async function abRefreshStudent() {
  if (!abStudents.length) {
    abStudents = must(await db.from("students").select("id, name, grade, is_active").order("is_active", { ascending: false }).order("grade").order("name"));
    $("ab-student").innerHTML = `<option value="">生徒を選んでください</option>` + abStudents.map(s =>
      `<option value="${s.id}">${esc(s.name)}（${esc(s.grade || "学年なし")}）${s.is_active ? "" : "・退塾"}</option>`).join("");
  }
  const id = $("ab-student").value;
  if (!id) { $("abv-student-body").innerHTML = `<section class="card"><p class="empty-note">生徒を選ぶと、振替ストックと欠席・振替の履歴が表示されます。</p></section>`; return; }
  const s = abStudents.find(x => x.id === id);
  $("ab-title").textContent = `${s.name}さん`;
  const [credits, abs, reqs] = await Promise.all([
    db.from("makeup_credits").select("*, class_absences(class_date, class_type)").eq("student_id", id).order("granted_on", { ascending: false }).limit(60).then(must),
    db.from("class_absences").select("*").eq("student_id", id).order("class_date", { ascending: false }).limit(60).then(must),
    db.from("makeup_requests").select("*").eq("student_id", id).order("class_date", { ascending: false }).limit(60).then(must),
  ]);
  const usable = credits.filter(c => creditStatus(c) === "available").length;
  $("abv-student-body").innerHTML = `
    <div class="kpis">
      <section class="card kpi"><span class="kpi-label">使える振替ストック</span><div class="kpi-bottom"><span class="kpi-value">${usable}<small>回</small></span></div></section>
      <section class="card kpi"><span class="kpi-label">欠席の連絡（全期間）</span><div class="kpi-bottom"><span class="kpi-value">${abs.filter(a => a.status === "registered").length}<small>回</small></span></div></section>
      <section class="card kpi"><span class="kpi-label">振替（承認）</span><div class="kpi-bottom"><span class="kpi-value">${reqs.filter(r => r.status === "approved").length}<small>回</small></span></div></section>
    </div>
    <div class="lower">
      <section class="card"><div class="card-head"><h2>振替ストック</h2></div>
        <form class="grant-form" id="ab-grant-form"><input type="text" id="ab-grant-note" maxlength="100" placeholder="理由（例：休講の補填）" aria-label="追加の理由">
          <button type="submit" class="btn small primary">＋ ストックを追加</button></form>
        ${credits.length ? `<div class="tablewrap"><table><thead><tr><th>もと</th><th>期限</th><th>状態</th><th>操作</th></tr></thead><tbody>${credits.map(c => {
          const stt = creditStatus(c);
          const from = c.class_absences ? `${fmtDay(c.class_absences.class_date)} ${classLabelA(c.class_absences.class_type)}の欠席` : esc(c.note || "追加");
          return `<tr data-credit="${c.id}"><td>${from}${c.class_absences && c.note ? `<br><small>${esc(c.note)}</small>` : ""}</td><td>${fmtDay(c.expires_on)}</td>
            <td><span class="pst pst-${AB_CREDIT_BADGE[stt]}">${AB_CREDIT_LABEL[stt]}</span></td>
            <td class="actions">${stt === "available" ? `<button type="button" class="btn small danger" data-abact="revoke-credit">取り消す</button>` : ""}</td></tr>`;
        }).join("")}</tbody></table></div>` : `<p class="empty-note">ストックはありません。</p>`}</section>
      <section class="card"><div class="card-head"><h2>履歴</h2></div>
        <h3>欠席の連絡</h3>${abs.length ? `<ul class="ab-hist">${abs.map(a => `<li>${fmtDay(a.class_date)} ${esc(classLabelA(a.class_type))}
          ${a.status === "cancelled" ? `<span class="pst pst-rejected">取り消し</span>` : ""}${a.reason ? `<br><small>${esc(a.reason)}</small>` : ""}</li>`).join("")}</ul>` : `<p class="empty-note">なし</p>`}
        <h3>振替の申請</h3>${reqs.length ? `<ul class="ab-hist">${reqs.map(r => `<li>${fmtDay(r.class_date)} ${esc(classLabelA(r.class_type))}
          <span class="pst pst-${AB_REQ_BADGE[r.status]}">${AB_REQ_LABEL[r.status]}</span>${r.reject_reason ? `<br><small>${esc(r.reject_reason)}</small>` : ""}</li>`).join("")}</ul>` : `<p class="empty-note">なし</p>`}
      </section>
    </div>`;
}
$("abv-student").addEventListener("submit", ev => {
  if (ev.target.id !== "ab-grant-form") return;
  ev.preventDefault();
  guard(async () => {
    const s = abStudents.find(x => x.id === $("ab-student").value);
    const note = $("ab-grant-note").value.trim();
    if (!confirm(`${s.name}さんに、振替ストックを1つ追加します${note ? `（${note}）` : ""}。\n\nよろしいですか？`)) return;
    must(await db.rpc("admin_grant_credit", { p_student_id: s.id, p_note: note }));
    toast("ストックを追加しました"); await abRefreshStudent();
  });
});

// ---------- 設定 ----------
async function abRefreshSettings() {
  const st = must(await db.from("makeup_settings").select("*").eq("id", 1).single());
  $("abs-months").value = st.credit_valid_months;
  $("abs-cap").value = st.makeup_capacity;
}
$("ab-settings-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    must(await db.from("makeup_settings").update({ credit_valid_months: +$("abs-months").value, makeup_capacity: +$("abs-cap").value }).eq("id", 1).select());
    toast("保存しました");
  });
});

// ---------- 操作（承認・却下・取り消し） ----------
$("tab-absence").addEventListener("click", ev => {
  const b = ev.target.closest("[data-abact]"); if (!b) return;
  const act = b.dataset.abact;
  if (act === "open-day") { $("ab-date").value = b.dataset.date; setAbView("day"); guard(abRefreshDay); return; }
  guard(async () => {
    if (act === "revoke-credit") {
      if (!confirm("この振替ストックを取り消します。元に戻せません。\n\nよろしいですか？")) return;
      must(await db.rpc("admin_revoke_credit", { p_credit_id: b.closest("[data-credit]").dataset.credit, p_note: "" }));
      toast("ストックを取り消しました"); return abRefreshStudent();
    }
    const r = abRows.find(x => x.id === b.closest("[data-id]")?.dataset.id);
    if (!r) return;
    const what = `${fmtDay(r.class_date)} ${classLabelA(r.class_type)}　${nameOf(r)}`;
    if (act === "approve") {
      if (!confirm(`${what}の振替を承認します。\n\nよろしいですか？`)) return;
      abLocal.add(r.id);
      must(await db.rpc("admin_approve_makeup", { p_request_id: r.id }));
      toast("振替を承認しました");
    } else if (act === "reject") {
      abRejecting = r;
      $("abr-who").textContent = what;
      $("abr-reason").selectedIndex = 0; $("abr-other").value = "";
      $("ab-reject-dlg").showModal();
      return;
    } else if (act === "cancel-makeup") {
      if (!confirm(`${what}の振替（承認済み）を取り消します。\n使った振替ストックは生徒に戻します。\n\nよろしいですか？`)) return;
      abLocal.add(r.id);
      must(await db.rpc("admin_cancel_makeup", { p_request_id: r.id, p_return: true }));
      toast("振替を取り消しました（ストックは戻しました）");
    }
    await refreshAbsenceAdmin();
  });
});
$("abr-cancel").onclick = () => $("ab-reject-dlg").close();
$("ab-reject-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const reason = $("abr-reason").value || $("abr-other").value.trim();
    if (!reason) throw new Error("理由を選ぶか、入力してください。");
    abLocal.add(abRejecting.id);
    must(await db.rpc("admin_reject_makeup", { p_request_id: abRejecting.id, p_reason: reason }));
    $("ab-reject-dlg").close(); toast("振替の申請を却下しました（ストックは戻りました）");
    await refreshAbsenceAdmin();
  });
});

// ---------- 「予定」タブの授業に、欠席・振替の人数を出す（admin.js の refreshEvents から呼ばれる） ----------
async function fetchMonthAttendance(from, to) {
  const [abs, reqs] = await Promise.all([
    db.from("class_absences").select("class_date, class_type").eq("status", "registered").gte("class_date", from).lte("class_date", to).then(must),
    db.from("makeup_requests").select("class_date, class_type, status").in("status", ["pending", "approved"]).gte("class_date", from).lte("class_date", to).then(must),
  ]);
  const map = new Map();
  const get = (d, t) => { const k = `${d}|${t}`; if (!map.has(k)) map.set(k, { absent: 0, makeup: 0, pending: 0 }); return map.get(k); };
  abs.forEach(a => get(a.class_date, a.class_type).absent++);
  reqs.forEach(r => { const c = get(r.class_date, r.class_type); if (r.status === "approved") c.makeup++; else c.pending++; });
  return map;
}
function attendanceTag(e, map) {
  const c = map?.get?.(`${e.event_date}|${e.type}`);
  if (!c) return "";
  return ` <span class="att-tag" title="欠席・振替の人数（管理画面だけに表示）">欠席${c.absent}・振替${c.makeup}${c.pending ? `（申請中${c.pending}）` : ""}</span>`;
}
