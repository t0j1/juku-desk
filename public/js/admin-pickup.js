"use strict";
// 管理画面：送迎（生徒・送迎設定）。admin.js のあとに読み込み、guard / must / toast を使う。
// 権限は画面ではなく DB の RLS と、DB 関数の is_admin() で守られている。

const WEEK_ORDER = [1, 2, 3, 4, 5, 6, 0];     // 表示は月曜はじまり
let students = [];
let editingStudentId = null;
let availability = [];
let editingAvId = null;
let pickupSettings = null;

document.querySelectorAll("#tabs button").forEach(b => b.addEventListener("click", () => {
  if (b.dataset.tab === "students") guard(refreshStudents);
  if (b.dataset.tab === "pickup-settings") guard(refreshPickupSettings);
}));

const jstDate = ts => new Date(ts).toLocaleDateString("ja-JP", { timeZone: "Asia/Tokyo", month: "numeric", day: "numeric", weekday: "short" });
const codeIsValid = c => c && new Date(c.expires_at) > new Date() && c.used_count < c.max_uses;
const activeContact = s => (s.student_contacts || []).find(c => c.is_active);

// ---------- 生徒 ----------
async function refreshStudents() {
  students = must(await db.from("students")
    .select("*, student_contacts(id, display_name, email, line_user_id, is_active, linked_at), student_link_codes(expires_at, used_count, max_uses)")
    .order("is_active", { ascending: false }).order("grade").order("name"));
  renderStudents();
}

function renderStudents() {
  const all = $("st-show-inactive").checked;
  const rows = students.filter(s => all || s.is_active);
  if (!rows.length) {
    $("st-list").innerHTML = `<p class="status">${students.length ? "在籍中の生徒はいません。" : "生徒はまだ登録されていません。「＋ 生徒を追加」から登録してください。"}</p>`;
    return;
  }
  $("st-list").innerHTML = `<table><thead><tr><th>名前</th><th>学年</th><th>電話番号</th><th>LINE</th><th>状態</th><th>操作</th></tr></thead><tbody>${
    rows.map(s => {
      const c = activeContact(s), code = (s.student_link_codes || [])[0];
      const line = c ? `<span class="line-ok">✓ 連携済み</span><br><small>${esc(c.display_name || c.email || "")}（${jstDate(c.linked_at)}）</small>`
        : codeIsValid(code) ? `<span class="line-wait">コード発行済み</span><br><small>${jstDate(code.expires_at)}まで有効</small>`
        : `<span class="line-none">未連携</span>`;
      return `<tr class="${s.is_active ? "" : "inactive"}" data-id="${s.id}">
        <td><strong>${esc(s.name)}</strong></td><td>${esc(s.grade)}</td><td>${esc(s.phone)}</td>
        <td>${line}</td><td>${s.is_active ? "在籍" : "退塾"}</td>
        <td class="actions">
          <button type="button" class="btn small" data-act="edit">編集</button>
          ${s.is_active ? `<button type="button" class="btn small" data-act="code">${c || codeIsValid(code) ? "コード再発行" : "登録コード"}</button>` : ""}
          ${c ? `<button type="button" class="btn small danger" data-act="unlink">連携解除</button>` : ""}
        </td></tr>`;
    }).join("")}</tbody></table>`;
}
$("st-show-inactive").addEventListener("change", renderStudents);

function openStudentForm(s) {
  editingStudentId = s ? s.id : null;
  $("st-dlg-title").textContent = s ? "生徒を編集" : "生徒を追加";
  $("s-name").value = s ? s.name : "";
  $("s-grade").value = s ? s.grade : "高1";
  $("s-phone").value = s ? s.phone : "";
  $("s-active").checked = s ? s.is_active : true;
  $("st-dlg").showModal();
}
$("st-add").onclick = () => openStudentForm(null);
$("st-cancel").onclick = () => $("st-dlg").close();
$("st-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const row = { name: $("s-name").value.trim(), grade: $("s-grade").value, phone: $("s-phone").value.trim(), is_active: $("s-active").checked };
    if (!row.name) throw new Error("名前を入力してください。");
    if (editingStudentId) must(await db.from("students").update(row).eq("id", editingStudentId).select());
    else must(await db.from("students").insert(row).select());
    $("st-dlg").close(); toast("保存しました");
    await refreshStudents();
  });
});

$("st-list").addEventListener("click", ev => {
  const b = ev.target.closest("[data-act]"); if (!b) return;
  const s = students.find(x => x.id === b.closest("tr").dataset.id);
  guard(async () => {
    if (b.dataset.act === "edit") openStudentForm(s);
    else if (b.dataset.act === "code") {
      const c = activeContact(s), old = (s.student_link_codes || [])[0];
      if (c && !confirm(`${s.name}さんは LINE と連携済みです。\n新しいコードを発行して生徒が入力すると、今の LINE との連携は解除されます（機種変更などのとき用）。\n\n発行しますか？`)) return;
      if (!c && codeIsValid(old) && !confirm(`${s.name}さんには、まだ使われていないコードがあります。\n再発行すると、前のコードは使えなくなります。\n\n発行しますか？`)) return;
      const code = must(await db.rpc("issue_link_code", { p_student_id: s.id }));
      showCode(s, code);
      await refreshStudents();
    } else if (b.dataset.act === "unlink") {
      if (!confirm(`${s.name}さんの LINE 連携を解除します。解除すると、その LINE からは予約できなくなります（予約の記録は残ります）。\n\nよろしいですか？`)) return;
      must(await db.from("student_contacts").update({ is_active: false }).eq("student_id", s.id).eq("is_active", true).select("id"));
      toast("連携を解除しました"); await refreshStudents();
    }
  });
});

function showCode(s, code) {
  const shown = `${code.slice(0, 4)}-${code.slice(4)}`;
  const until = new Date(Date.now() + 14 * 864e5);
  $("code-for").textContent = `${s.name}さん（${s.grade || "学年なし"}）`;
  $("code-value").textContent = shown;
  $("code-text").value = [
    "【碩学館 送迎予約】",
    `${s.name}さんの登録コード：${shown}`,
    `有効期限：${jstDate(until)}まで（1回だけ使えます）`,
    "碩学館の LINE 公式アカウントのメニュー「送迎予約」を開き、このコードを入力してください。",
  ].join("\n");
  $("code-dlg").showModal();
}
$("code-copy").onclick = () => guard(async () => {
  try { await navigator.clipboard.writeText($("code-text").value); toast("コピーしました"); }
  catch { $("code-text").select(); toast("コピーできませんでした。文面を選択したので、手動でコピーしてください。", true); }
});
$("code-close").onclick = () => $("code-dlg").close();

// ---------- 送迎設定 ----------
$("av-wd").innerHTML = WEEK_ORDER.map(i => `<label><input type="checkbox" value="${i}"> ${DOW[i]}</label>`).join("");
$("ae-dow").innerHTML = WEEK_ORDER.map(i => `<option value="${i}">${DOW[i]}曜日</option>`).join("");
$("av-form").querySelectorAll("[data-wd]").forEach(b => b.onclick = () => {
  const on = b.dataset.wd ? b.dataset.wd.split(",") : [];
  $("av-wd").querySelectorAll("input").forEach(i => { i.checked = on.includes(i.value); });
});

async function refreshPickupSettings() {
  const [av, ps] = await Promise.all([
    db.from("pickup_availability").select("*").order("day_of_week").order("start_time"),
    db.from("pickup_settings").select("*").eq("id", 1).single(),
  ]);
  availability = must(av);
  pickupSettings = must(ps);
  renderAvailability();
  $("ps-place").value = pickupSettings.pickup_place;
  $("ps-slot").value = String(pickupSettings.slot_minutes);
  $("ps-trip").value = pickupSettings.trip_minutes;
  $("ps-lead").value = pickupSettings.min_lead_minutes;
  $("ps-adv").value = pickupSettings.max_advance_days;
  $("ps-tol").value = pickupSettings.tolerance_minutes;
  $("ps-cap").value = pickupSettings.default_capacity;
  $("ps-mail").value = pickupSettings.admin_notify_email || "";
}

function renderAvailability() {
  if (!availability.length) { $("av-list").innerHTML = `<p class="status">送迎時間帯はまだありません。下のフォームから追加してください。</p>`; return; }
  const rank = d => WEEK_ORDER.indexOf(d);
  const rows = [...availability].sort((a, b) => rank(a.day_of_week) - rank(b.day_of_week) || a.start_time.localeCompare(b.start_time));
  const trip = pickupSettings?.trip_minutes ?? 15;
  $("av-list").innerHTML = `<table><thead><tr><th>曜日</th><th>時間帯</th><th>最終便</th><th>定員</th><th>状態</th><th>操作</th></tr></thead><tbody>${
    rows.map(a => `<tr class="${a.is_active ? "" : "inactive"}" data-id="${a.id}">
      <td><strong>${DOW[a.day_of_week]}</strong></td>
      <td>${hhmm(a.start_time)}〜${hhmm(a.end_time)}</td>
      <td>${fromMin(toMin(hhmm(a.end_time)) - trip)}</td>
      <td>${a.max_capacity}人</td>
      <td><button type="button" class="state ${a.is_active ? "pub" : "draft"}" data-act="toggle" title="クリックで切り替え">${a.is_active ? "● 有効" : "○ 無効"}</button></td>
      <td class="actions"><button type="button" class="btn small" data-act="edit">編集</button><button type="button" class="btn small danger" data-act="del">削除</button></td>
    </tr>`).join("")}</tbody></table>`;
}

$("av-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const days = [...$("av-wd").querySelectorAll("input:checked")].map(i => +i.value);
    if (!days.length) throw new Error("曜日を1つ以上選んでください。");
    const start = $("av-start").value, end = $("av-end").value, cap = +$("av-cap").value;
    if (end <= start) throw new Error("終了時刻は開始時刻より後にしてください。");
    // 1回の insert にまとめる（どれか1つでも重なれば、全部登録しない）
    must(await db.from("pickup_availability").insert(days.map(d => ({ day_of_week: d, start_time: start, end_time: end, max_capacity: cap }))).select("id"));
    toast(`${days.map(d => DOW[d]).join("・")} に ${start}〜${end} を追加しました`);
    $("av-wd").querySelectorAll("input").forEach(i => { i.checked = false; });
    await refreshPickupSettings();
  });
});

$("av-list").addEventListener("click", ev => {
  const b = ev.target.closest("[data-act]"); if (!b) return;
  const a = availability.find(x => x.id === b.closest("tr").dataset.id);
  guard(async () => {
    if (b.dataset.act === "toggle") {
      must(await db.from("pickup_availability").update({ is_active: !a.is_active }).eq("id", a.id).select());
      toast(a.is_active ? "無効にしました" : "有効にしました"); await refreshPickupSettings();
    } else if (b.dataset.act === "edit") {
      editingAvId = a.id;
      $("ae-dow").value = String(a.day_of_week);
      $("ae-start").value = hhmm(a.start_time); $("ae-end").value = hhmm(a.end_time);
      $("ae-cap").value = a.max_capacity; $("ae-active").checked = a.is_active;
      $("av-dlg").showModal();
    } else if (b.dataset.act === "del") {
      if (!confirm(`${DOW[a.day_of_week]}曜日 ${hhmm(a.start_time)}〜${hhmm(a.end_time)} を削除します。\n（すでに入っている予約は消えません）\n\nよろしいですか？`)) return;
      must(await db.from("pickup_availability").delete().eq("id", a.id).select("id"));
      toast("削除しました"); await refreshPickupSettings();
    }
  });
});
$("av-cancel").onclick = () => $("av-dlg").close();
$("av-edit-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const row = { day_of_week: +$("ae-dow").value, start_time: $("ae-start").value, end_time: $("ae-end").value,
                  max_capacity: +$("ae-cap").value, is_active: $("ae-active").checked };
    if (row.end_time <= row.start_time) throw new Error("終了時刻は開始時刻より後にしてください。");
    must(await db.from("pickup_availability").update(row).eq("id", editingAvId).select());
    $("av-dlg").close(); toast("保存しました"); await refreshPickupSettings();
  });
});

$("ps-form").addEventListener("submit", e => {
  e.preventDefault();
  guard(async () => {
    const row = {
      pickup_place: $("ps-place").value.trim(), slot_minutes: +$("ps-slot").value, trip_minutes: +$("ps-trip").value,
      min_lead_minutes: +$("ps-lead").value, max_advance_days: +$("ps-adv").value, tolerance_minutes: +$("ps-tol").value,
      default_capacity: +$("ps-cap").value, admin_notify_email: $("ps-mail").value.trim() || null,
    };
    must(await db.from("pickup_settings").update(row).eq("id", 1).select());
    toast("保存しました"); await refreshPickupSettings();
  });
});
