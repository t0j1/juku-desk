"use strict";
// 生徒用：欠席の連絡と振替の申請（pickup.html の「欠席・振替」タブ）。
// 通信は pickup.js の api() を使う（Edge Function pickup-api 経由。テーブルには直接触れない）。pickup.js のあとに読み込む。

const REQ_LABEL = { pending: "申請中", approved: "承認", rejected: "却下", cancelled: "取り消し" };
const REQ_BADGE = { pending: "pending", approved: "approved", rejected: "rejected", cancelled: "cancelled" };
const CREDIT_LABEL = { available: "使えます", reserved: "申請中に使用", used: "使用済み", expired: "期限切れ" };
const CREDIT_BADGE = { available: "approved", reserved: "proposing", used: "rejected", expired: "cancelled" };
const classLabel = t => String(t).replace("授業", "の授業");          // 高1授業 → 高1の授業
const timeRange = c => (c.start_time ? `${c.start_time}〜${c.end_time || ""}` : "");
let openAbsenceForm = null;   // 「休む」を押して理由を入力中の授業（日付＋種別）

// ---------- タブの切り替え ----------
document.querySelectorAll(".page-tabs button").forEach(b => b.addEventListener("click", () => showPage(b.dataset.page)));
function showPage(page) {
  document.querySelectorAll(".page-tabs button").forEach(b => {
    const on = b.dataset.page === page;
    b.classList.toggle("active", on); b.setAttribute("aria-pressed", String(on));
  });
  $("page-pickup").hidden = page !== "pickup";
  $("page-absence").hidden = page !== "absence";
  try { history.replaceState(null, "", page === "absence" ? "#absence" : location.pathname + location.search); } catch { /* 変えられなくても続ける */ }
  if (page === "absence") refreshAbsence();
}
function abMessage(text, isError) {
  const m = $("ab-msg");
  m.hidden = !text; m.textContent = text || ""; m.classList.toggle("error", !!isError);
}

// ---------- 読み込み ----------
async function refreshAbsence() {
  try {
    const [cls, mk, opts] = await Promise.all([api("classes"), api("makeup"), api("makeup_options")]);
    renderCredits(mk.credits);
    renderClasses(cls.classes);
    renderOptions(opts.options, mk.credits);
    renderRequests(mk.requests);
  } catch (e) {
    abMessage(e.message, true);
  }
}
$("ab-refresh").onclick = () => { abMessage(""); refreshAbsence(); };

function renderCredits(credits) {
  const usable = credits.filter(c => c.status === "available");
  $("ab-count").textContent = usable.length;
  $("ab-credits").innerHTML = credits.length ? credits.map(c => `<li class="ab-item">
      <div><strong>${c.from_date ? `${fmtDay(c.from_date)} ${esc(classLabel(c.from_type))}の欠席分` : esc(c.note || "追加されたストック")}</strong>
        <div class="ab-sub">期限：${fmtDay(c.expires_on)}まで</div></div>
      <span class="pst pst-${CREDIT_BADGE[c.status]}">${CREDIT_LABEL[c.status] || esc(c.status)}</span></li>`).join("")
    : `<li class="ab-empty">ストックはありません。</li>`;
}

function renderClasses(classes) {
  $("ab-class-list").innerHTML = classes.length ? classes.map(c => {
    const key = `${c.class_date}|${c.class_type}`;
    let right;
    if (c.absence_id) {
      right = `<span class="pst pst-pending">欠席連絡済み</span>
        ${c.can_cancel ? `<button type="button" class="btn small" data-act="absence-cancel" data-id="${esc(c.absence_id)}">取り消す</button>` : ""}`;
    } else if (c.can_register) {
      right = openAbsenceForm === key ? "" : `<button type="button" class="btn small danger" data-act="absence-open" data-key="${esc(key)}">休む</button>`;
    } else {
      right = `<span class="ab-sub">受付終了</span>`;
    }
    const form = openAbsenceForm === key && !c.absence_id ? `<div class="ab-form">
        <label>理由（任意）<input type="text" class="ab-reason" maxlength="200" placeholder="例：体調不良のため"></label>
        <div class="cols"><button type="button" class="btn" data-act="absence-close">やめる</button>
        <button type="button" class="btn primary" data-act="absence-send" data-date="${esc(c.class_date)}" data-type="${esc(c.class_type)}">欠席を連絡する</button></div></div>` : "";
    return `<li class="ab-item${c.absence_id ? " is-absent" : ""}">
      <div><strong>${fmtDay(c.class_date)}</strong> ${esc(classLabel(c.class_type))}
        <div class="ab-sub">${esc(timeRange(c))}${c.reason ? `　理由：${esc(c.reason)}` : ""}</div></div>
      <div class="ab-actions">${right}</div>${form}</li>`;
  }).join("") : `<li class="ab-empty">今後60日の授業はありません。</li>`;
}

function renderOptions(options, credits) {
  const usable = credits.filter(c => c.status === "available");
  if (!usable.length) { $("ab-options").innerHTML = `<li class="ab-empty">使える振替ストックがないため、申請できません。</li>`; return; }
  if (!options.length) { $("ab-options").innerHTML = `<li class="ab-empty">ストックの期限内に、申請できる授業がありません。</li>`; return; }
  $("ab-options").innerHTML = options.map(o => `<li class="ab-item">
      <div><strong>${fmtDay(o.class_date)}</strong> ${esc(classLabel(o.class_type))}
        <div class="ab-sub">${esc(timeRange(o))}　振替の残り ${o.remaining}人</div></div>
      <div class="ab-actions">${o.requested ? `<span class="pst pst-pending">申請済み</span>`
        : `<button type="button" class="btn small primary" data-act="makeup-send" data-date="${esc(o.class_date)}" data-type="${esc(o.class_type)}"${o.remaining ? "" : " disabled"}>${o.remaining ? "振替を申請" : "満員"}</button>`}</div></li>`).join("");
}

function renderRequests(requests) {
  $("ab-request-list").innerHTML = requests.length ? requests.map(r => `<li class="ab-item">
      <div><strong>${fmtDay(r.class_date)}</strong> ${esc(classLabel(r.class_type))}
        <div class="ab-sub">${esc(timeRange(r))}${r.reject_reason ? `　理由：${esc(r.reject_reason)}` : ""}</div>
        ${r.status === "approved" ? `<div class="ab-sub ok">この授業に出席できます。送迎が必要なら「送迎」から予約してください。</div>` : ""}</div>
      <div class="ab-actions"><span class="pst pst-${REQ_BADGE[r.status]}">${REQ_LABEL[r.status] || esc(r.status)}</span>
        ${r.status === "approved" ? `<button type="button" class="btn small" data-act="to-pickup" data-date="${esc(r.class_date)}">送迎を予約</button>` : ""}
        ${r.can_cancel ? `<button type="button" class="btn small" data-act="makeup-cancel" data-id="${esc(r.id)}">取り消す</button>` : ""}</div></li>`).join("")
    : `<li class="ab-empty">振替の申請はありません。</li>`;
}

// ---------- 操作 ----------
$("page-absence").addEventListener("click", async ev => {
  const b = ev.target.closest("[data-act]"); if (!b) return;
  const act = b.dataset.act;
  if (act === "absence-open") { openAbsenceForm = b.dataset.key; abMessage(""); return refreshAbsence().then(() => document.querySelector(".ab-reason")?.focus()); }
  if (act === "absence-close") { openAbsenceForm = null; return refreshAbsence(); }
  if (act === "to-pickup") { showPage("pickup"); $("b-date").value = b.dataset.date; $("b-date").dispatchEvent(new Event("change")); return; }
  b.disabled = true;
  try {
    if (act === "absence-send") {
      const d = b.dataset.date, t = b.dataset.type;
      await api("absence", { date: d, type: t, reason: b.closest(".ab-item").querySelector(".ab-reason")?.value.trim() || "" });
      openAbsenceForm = null;
      abMessage(`${fmtDay(d)} ${classLabel(t)}の欠席を連絡しました。振替ストックが1つ増えました。`);
      await offerPickupCancel(d);
    } else if (act === "absence-cancel") {
      if (!confirm("欠席の連絡を取り消します。この欠席の振替ストックも消えます。\n\nよろしいですか？")) return;
      await api("absence_cancel", { id: b.dataset.id });
      abMessage("欠席の連絡を取り消しました。");
    } else if (act === "makeup-send") {
      const d = b.dataset.date, t = b.dataset.type;
      if (!confirm(`${fmtDay(d)} ${classLabel(t)}に、振替を申請します（ストックを1つ使います）。\n\nよろしいですか？`)) return;
      await api("makeup_request", { date: d, type: t });
      abMessage(`${fmtDay(d)} ${classLabel(t)}に振替を申請しました。管理者の承認をお待ちください。`);
      if (typeof celebrateCat === "function") celebrateCat("にゃ！振替を申請したよ");
    } else if (act === "makeup-cancel") {
      if (!confirm("振替の申請を取り消します。使ったストックは戻ります。\n\nよろしいですか？")) return;
      await api("makeup_cancel", { id: b.dataset.id });
      abMessage("振替の申請を取り消しました。ストックは戻りました。");
    }
  } catch (e) {
    abMessage(e.message, true);
  } finally {
    b.disabled = false;
    await refreshAbsence();
  }
});

// 欠席する日に送迎の予約があれば、取り消すか聞く
async function offerPickupCancel(date) {
  try {
    const { reservations } = await api("mine");
    const same = reservations.filter(r => r.pickup_date === date && r.can_cancel);
    for (const r of same) {
      const t = r.approved_time || r.pickup_time;
      if (confirm(`${fmtDay(date)} ${t} 発の送迎予約があります。送迎も取り消しますか？`)) {
        await api("cancel", { id: r.id });
        abMessage(`${fmtDay(date)}の欠席を連絡し、送迎予約も取り消しました。`);
      }
    }
    await refreshMine();
  } catch (e) {
    abMessage(`欠席は連絡しましたが、送迎予約の確認に失敗しました：${e.message}`, true);
  }
}
