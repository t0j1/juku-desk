"use strict";
// 相乗りの打診への回答ページ（開発用のリンク／LINE の準備ができるまでの手渡し用）。
// リンクを開いただけでは回答しない（メールのセキュリティ確認などで自動的に開かれることがあるため）。ボタンを押したときだけ回答する。

const API = `${SUPABASE_URL}/functions/v1/pickup-api`;
const token = new URLSearchParams(location.search).get("t") || "";
const ANSWERED = { accepted: "「変更してよい」と回答済みです。", declined: "「できない」と回答済みです。", expired: "回答の期限が過ぎています。碩学館に直接ご連絡ください。" };

// 回答後は、URL からトークンを消しておく（履歴や画面の共有で残らないように）
const hideToken = () => { try { history.replaceState(null, "", location.pathname); } catch { /* 消せなくても続ける */ } };

async function api(action, params) {
  const res = await fetch(API, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: SUPABASE_ANON_KEY },
    body: JSON.stringify({ action, token, ...params }),
  });
  let body = {};
  try { body = await res.json(); } catch { /* 本文なし */ }
  if (!res.ok) throw new Error(body.error || `通信に失敗しました（${res.status}）。`);
  return body;
}

function showResult(text) {
  $("buttons").hidden = true;
  $("result").hidden = false;
  $("result").textContent = text;
}

async function load() {
  if (!/^[0-9a-f]{64}$/.test(token)) { $("status").textContent = "このリンクは正しくありません。"; $("status").classList.add("error"); return; }
  try {
    const { proposal: p } = await api("proposal", {});
    $("who").textContent = `${p.student_name}さん`;
    $("r-date").textContent = fmtDay(p.pickup_date);
    $("r-orig").textContent = `${p.pickup_time} 発`;
    $("r-new").textContent = `${p.proposed_time} 発`;
    $("r-new2").textContent = p.proposed_time;
    $("r-exp").textContent = `回答の期限：${new Date(p.expires_at).toLocaleString("ja-JP", { timeZone: "Asia/Tokyo", month: "numeric", day: "numeric", hour: "2-digit", minute: "2-digit" })}`;
    $("status").hidden = true;
    $("card").hidden = false;
    if (ANSWERED[p.response]) showResult(ANSWERED[p.response]);
  } catch (e) {
    $("status").textContent = e.message; $("status").classList.add("error");
  }
}

$("buttons").addEventListener("click", async ev => {
  const b = ev.target.closest("[data-accept]"); if (!b) return;
  const accept = b.dataset.accept === "1";
  $("buttons").querySelectorAll("button").forEach(x => { x.disabled = true; });
  try {
    const r = await api("respond_token", { accept });
    hideToken();
    showResult(accept
      ? (r.group_status === "confirmed" ? `ありがとうございます。送迎時刻は ${$("r-new2").textContent} 発で確定しました。` : "ありがとうございます。ほかの生徒の回答がそろうと確定します。")
      : "回答を受け付けました。碩学館から改めてご連絡します。");
  } catch (e) {
    alert(e.message);
    $("buttons").querySelectorAll("button").forEach(x => { x.disabled = false; });
  }
});

load();
