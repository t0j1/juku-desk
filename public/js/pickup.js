"use strict";
// 送迎予約（生徒用）。予約・取り消し・回答は Edge Function pickup-api を通す（DB のテーブルには直接触れない）。
// 本番は LINE（LIFF）から開いて LINE で本人確認する。開発用 DB のときは、メールアドレスで本人を識別する。

const API = typeof SUPABASE_URL === "string" ? `${SUPABASE_URL}/functions/v1/pickup-api` : "";
const DEV = typeof SUPABASE_ENV === "string" && SUPABASE_ENV === "dev";
const EMAIL_KEY = "pickup_dev_email";
let info = null;          // get_pickup_info の結果
let chosen = null;        // 選んだ時刻 "HH:MM"
let slotToken = 0;        // 日付を続けて変えたとき、古い応答で上書きしないように

// localStorage は使えないこともある（プライベートブラウズなど）
const store = {
  get: k => { try { return localStorage.getItem(k); } catch { return null; } },
  set: (k, v) => { try { localStorage.setItem(k, v); } catch { /* 保存できなくても続ける */ } },
  del: k => { try { localStorage.removeItem(k); } catch { /* 同上 */ } },
};

function setStatus(text, isError) {
  const s = $("status");
  s.hidden = !text; s.textContent = text || ""; s.classList.toggle("error", !!isError);
}
function setMsg(id, text) { $(id).textContent = text || ""; }
function show(section) { ["sec-login", "sec-link", "sec-main"].forEach(id => { $(id).hidden = id !== section; }); }

async function api(action, params = {}) {
  const auth = DEV ? { email: store.get(EMAIL_KEY) || "" } : {};
  let res;
  try {
    res = await fetch(API, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: SUPABASE_ANON_KEY },
      body: JSON.stringify({ action, ...auth, ...params }),
    });
  } catch {
    throw new Error("通信できませんでした。電波の良いところで、もう一度お試しください。");
  }
  let body = {};
  try { body = await res.json(); } catch { /* 本文なし */ }
  if (!res.ok) {
    const e = new Error(body.error || `通信に失敗しました（${res.status}）。`);
    e.status = res.status;
    throw e;
  }
  return body;
}

// ---------- 起動・本人確認 ----------
async function boot() {
  if (!db || !API) { setStatus("接続設定（js/config.js）が未入力です。", true); return; }
  document.querySelectorAll(".dev-only").forEach(el => { el.hidden = !DEV; });
  setStatus("読み込み中…");
  try {
    const { data, error } = await db.rpc("get_pickup_info");
    if (error) throw error;
    info = data;
    $("place").textContent = info.place;
  } catch (e) {
    console.error(e); setStatus("読み込みに失敗しました。時間をおいて開き直してください。", true); return;
  }
  if (!DEV) {
    // 本番（LINE から開く）はフェーズ6bで対応する
    setStatus("送迎予約は、碩学館の LINE 公式アカウントのメニューから開いてください。", false);
    return;
  }
  if (!store.get(EMAIL_KEY)) { setStatus(""); show("sec-login"); return; }
  await whoAmI();
}

async function whoAmI() {
  try {
    const me = await api("me");
    setStatus("");
    if (!me.linked) { show("sec-link"); return; }
    $("who-name").textContent = `${me.student_name}さん${me.grade ? `（${me.grade}）` : ""}`;
    show("sec-main");
    resetBooking();
    await refreshMine();
  } catch (e) {
    setStatus(e.message, true);
  }
}

$("login-form").addEventListener("submit", ev => {
  ev.preventDefault();
  store.set(EMAIL_KEY, $("login-mail").value.trim());
  whoAmI();
});
document.addEventListener("click", ev => {
  if (!ev.target.closest("[data-act=change-mail]")) return;
  store.del(EMAIL_KEY);
  $("login-mail").value = "";
  setStatus(""); show("sec-login");
});

$("link-form").addEventListener("submit", async ev => {
  ev.preventDefault();
  setMsg("link-msg", "");
  const btn = ev.submitter; btn.disabled = true;
  try {
    await api("link", { code: $("link-code").value });
    $("link-code").value = "";
    await whoAmI();
  } catch (e) {
    setMsg("link-msg", e.message);
  } finally { btn.disabled = false; }
});

// ---------- 予約 ----------
function resetBooking() {
  $("book-form").hidden = false; $("confirm").hidden = true; $("done").hidden = true;
  $("b-date").min = info.today; $("b-date").max = info.max_date;
  $("b-date").value = ""; $("b-notes").value = "";
  $("slot-box").hidden = true; $("slots").innerHTML = "";
  setMsg("date-msg", `${fmtDay(info.today)} 〜 ${fmtDay(info.max_date)} の間で選べます。`);
  chosen = null; updateConfirmButton();
}
const updateConfirmButton = () => { $("to-confirm").disabled = !($("b-date").value && chosen); };

async function loadSlots() {
  const date = $("b-date").value;
  chosen = null; updateConfirmButton();
  $("slots").innerHTML = ""; $("slot-box").hidden = true;
  if (!date) return;
  if (date < info.today || date > info.max_date) { setMsg("date-msg", `${fmtDay(info.today)} 〜 ${fmtDay(info.max_date)} の間で選んでください。`); return; }
  const dow = new Date(date + "T00:00:00").getDay();
  if (!info.days.includes(dow)) { setMsg("date-msg", `${DOW[dow]}曜日は送迎がありません。`); return; }
  setMsg("date-msg", "時刻を読み込み中…");
  const token = ++slotToken;
  const { data, error } = await db.rpc("get_pickup_slots", { p_date: date });
  if (token !== slotToken) return;
  if (error) { console.error(error); setMsg("date-msg", "時刻の読み込みに失敗しました。もう一度日付を選んでください。"); return; }
  if (!data.length) { setMsg("date-msg", "この日は予約できる時刻がありません（休講日、または受付時間を過ぎています）。"); return; }
  const open = data.filter(s => s.remaining > 0).length;
  setMsg("date-msg", open ? `${fmtDay(date)}：時刻を選んでください。` : "この日はすべて満席です。");
  $("slots").innerHTML = data.map(s => {
    const sub = s.remaining === 0 ? "満席" : s.is_group ? `相乗り便・残り${s.remaining}` : `残り${s.remaining}`;
    return `<button type="button" class="slot${s.is_group ? " group" : ""}" role="radio" aria-checked="false" data-t="${esc(s.slot)}"${s.remaining === 0 ? " disabled" : ""}>
      <span class="t">${esc(s.slot)}</span><span class="sub">${sub}</span></button>`;
  }).join("");
  $("slot-box").hidden = false;
}
$("b-date").addEventListener("change", loadSlots);

$("slots").addEventListener("click", ev => {
  const b = ev.target.closest(".slot"); if (!b || b.disabled) return;
  chosen = b.dataset.t;
  $("slots").querySelectorAll(".slot").forEach(x => x.setAttribute("aria-checked", String(x === b)));
  updateConfirmButton();
});

$("book-form").addEventListener("submit", ev => {
  ev.preventDefault();
  if (!chosen) return;
  $("c-date").textContent = fmtDay($("b-date").value);
  $("c-time").textContent = `${chosen} 発`;
  $("c-place").textContent = info.place;
  $("c-notes").textContent = $("b-notes").value.trim() || "（なし）";
  setMsg("book-msg", "");
  $("book-form").hidden = true; $("confirm").hidden = false;
  $("submit").focus();
});
$("back").onclick = () => { $("confirm").hidden = true; $("book-form").hidden = false; };

$("submit").onclick = async () => {
  const btn = $("submit"); btn.disabled = true; setMsg("book-msg", "");
  try {
    await api("submit", { date: $("b-date").value, time: chosen, notes: $("b-notes").value.trim() });
    $("confirm").hidden = true; $("done").hidden = false;
    $("done-note").textContent = DEV ? "承認されると、メールでお知らせします（開発中）。" : "承認されると、LINE でお知らせします。";
    await refreshMine();
  } catch (e) {
    setMsg("book-msg", e.message);
    // 満席などで選べなくなった場合は、選び直してもらう
    if (e.status === 400) { $("confirm").hidden = true; $("book-form").hidden = false; await loadSlots(); setMsg("date-msg", e.message); }
    if (e.status === 403) await whoAmI();
  } finally { btn.disabled = false; }
};
$("again").onclick = () => resetBooking();

// ---------- 自分の予約 ----------
async function refreshMine() {
  const box = $("mine-list");
  try {
    const { reservations } = await api("mine");
    if (!reservations.length) { box.innerHTML = `<p class="status">今後の予約はありません。</p>`; return; }
    box.innerHTML = reservations.map(r => {
      const st = pickupStatusOf(r);
      const time = r.approved_time ? `${r.approved_time} 発` : `${r.pickup_time} 発（希望）`;
      const proposal = r.proposal_id ? `<div class="proposal" data-pid="${esc(r.proposal_id)}">
          <p>ほかの生徒との相乗りのため、<strong>${esc(r.proposed_time)}</strong> 発に変更できますか？</p>
          <div class="cols"><button class="btn primary" type="button" data-act="accept">変更してよい</button>
          <button class="btn" type="button" data-act="decline">できない</button></div></div>` : "";
      return `<article class="res-card st-${st}" data-id="${esc(r.id)}">
        <div class="res-head"><strong>${fmtDay(r.pickup_date)}</strong> ${pickupBadge(st)}</div>
        <div class="res-time">${esc(time)}</div>
        ${r.status === "rejected" && r.reject_reason ? `<div class="res-note">理由：${esc(r.reject_reason)}</div>` : ""}
        ${r.notes ? `<div class="res-note">備考：${esc(r.notes)}</div>` : ""}
        ${proposal}
        ${r.can_cancel ? `<button class="btn small danger" type="button" data-act="cancel">取り消す</button>` : ""}
      </article>`;
    }).join("");
  } catch (e) {
    box.innerHTML = `<p class="status error">${esc(e.message)}</p>`;
  }
}
$("mine-refresh").onclick = refreshMine;

$("mine-list").addEventListener("click", async ev => {
  const b = ev.target.closest("[data-act]"); if (!b) return;
  const card = b.closest(".res-card");
  b.disabled = true;
  try {
    if (b.dataset.act === "cancel") {
      if (!confirm(`${card.querySelector(".res-head strong").textContent} の予約を取り消します。よろしいですか？`)) return;
      await api("cancel", { id: card.dataset.id });
    } else {
      const r = await api("respond", { proposal_id: b.closest(".proposal").dataset.pid, accept: b.dataset.act === "accept" });
      if (r.group_status === "confirmed") alert("送迎時刻が確定しました。");
    }
    await refreshMine();
    if (!$("book-form").hidden && $("b-date").value) await loadSlots();
  } catch (e) {
    alert(e.message);
    await refreshMine();
  } finally { b.disabled = false; }
});

boot();
