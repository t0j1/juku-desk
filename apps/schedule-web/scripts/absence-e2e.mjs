// 欠席・振替の通しのテスト（開発用 Supabase に対して実際に行う）。
// 高1・高2の生徒を作り、見本の授業を入れて、欠席の連絡 → ストック → 振替の申請 → 承認 → 取り消し までを確かめる。
// 作ったテストデータ（名前が「E2Eテスト」で始まる生徒、内容が「E2Eテスト授業」の予定）は最後に消す。
//
// 準備・実行は scripts/pickup-e2e.mjs と同じ（.env.dev に ADMIN_EMAIL / ADMIN_PASSWORD）: node scripts/absence-e2e.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = p => readFileSync(new URL(`../${p}`, import.meta.url), "utf8");
const cfg = read("public/js/config.js");
const [, URL_, KEY] = cfg.match(/dev:\s*\{\s*url:\s*"([^"]+)",\s*key:\s*"([^"]+)"/) || [];
if (!URL_ || URL_ === cfg.match(/prod:\s*\{\s*url:\s*"([^"]+)"/)?.[1]) throw new Error("開発用の接続先を読めません（または本番と同じです）。中止します");
let env = {};
try {
  env = Object.fromEntries(read(".env.dev").split(/\r?\n/).filter(l => /^\s*[A-Z_]+\s*=/.test(l))
    .map(l => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^["']|["']$/g, "")]; }));
} catch { /* 環境変数から */ }
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || env.ADMIN_EMAIL, ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || env.ADMIN_PASSWORD;
if (!ADMIN_EMAIL || !ADMIN_PASSWORD) { console.error(".env.dev に ADMIN_EMAIL= / ADMIN_PASSWORD= を書いてください"); process.exit(2); }

const PREFIX = "E2Eテスト", CLASS_TITLE = "E2Eテスト授業";
let token = null;
async function http(method, path, { body, auth = true } = {}) {
  const res = await fetch(URL_ + path, {
    method, body: body === undefined ? undefined : JSON.stringify(body),
    headers: { apikey: KEY, "Content-Type": "application/json", Prefer: "return=representation", ...(auth && token ? { Authorization: `Bearer ${token}` } : {}) },
  });
  const text = await res.text(); const data = text ? JSON.parse(text) : null;
  if (!res.ok) { const e = new Error(`${method} ${path} → ${res.status} ${data?.message || data?.error || text}`); e.body = data; throw e; }
  return data;
}
const rest = (m, p, b) => http(m, `/rest/v1/${p}`, { body: b });
const rpc = (fn, a, auth = true) => http("POST", `/rest/v1/rpc/${fn}`, { body: a, auth });
const student = (s, action, params = {}) => http("POST", "/functions/v1/pickup-api", { body: { action, email: s.email, ...params }, auth: false });
let passed = 0;
const ok = l => { passed++; console.log("  ✔", l); };
async function rejects(p, re, label) {
  try { await p; } catch (e) { assert.match(String(e.body?.error || e.message), re, `${label}: ${e.message}`); return; }
  assert.fail(`${label}: 失敗するはずが成功した`);
}

async function cleanup() {
  const ss = await rest("GET", `students?select=id&name=like.${encodeURIComponent(PREFIX + "*")}`);
  const ids = ss.map(s => s.id).join(",");
  if (ids) {
    await rest("DELETE", `makeup_requests?student_id=in.(${ids})`);
    await rest("DELETE", `makeup_credits?student_id=in.(${ids})`);
    await rest("DELETE", `class_absences?student_id=in.(${ids})`);
    const res = await rest("GET", `pickup_reservations?select=id,group_id&student_id=in.(${ids})`);
    if (res.length) await rest("DELETE", `pickup_reservations?student_id=in.(${ids})`);
    await rest("DELETE", `students?id=in.(${ids})`);
  }
  await rest("DELETE", `events?title=eq.${encodeURIComponent(CLASS_TITLE)}`);
  return ss.length;
}

async function main() {
  console.log(`接続先: ${URL_}（開発用）`);
  token = (await http("POST", "/auth/v1/token?grant_type=password", { body: { email: ADMIN_EMAIL, password: ADMIN_PASSWORD }, auth: false })).access_token;
  if (await cleanup()) console.log("  （前回のテストデータを消しました）");

  // 見本の授業：休講・授業のない、20日以降の日を2日（高2の授業の日と、高1の授業の日）
  const info = await rpc("get_pickup_info", {}, false);
  const plus = n => { const d = new Date(`${info.today}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
  const busy = new Set((await rest("GET", `events?select=event_date&event_date=gte.${plus(20)}&event_date=lte.${plus(40)}&type=in.(${encodeURIComponent("高1授業,高2授業,高3授業,休講,休暇")})`)).map(e => e.event_date));
  const free = Array.from({ length: 21 }, (_, i) => plus(20 + i)).filter(d => !busy.has(d));
  if (free.length < 2) throw new Error("見本の授業を入れられる日がありません");
  const [dA, dB] = free;
  await rest("POST", "events", [
    { event_date: dA, type: "高2授業", title: CLASS_TITLE, start_time: "18:30", end_time: "21:40", is_published: true },
    { event_date: dB, type: "高1授業", title: CLASS_TITLE, start_time: "18:30", end_time: "21:40", is_published: true },
  ]);

  const S2 = { name: `${PREFIX}高2`, grade: "高2", email: "e2e-ab-2@example.test" }, S1 = { name: `${PREFIX}高1`, grade: "高1", email: "e2e-ab-1@example.test" };
  for (const s of [S2, S1]) {
    [s.row] = await rest("POST", "students", { name: s.name, grade: s.grade });
    await student(s, "link", { code: await rpc("issue_link_code", { p_student_id: s.row.id }) });
  }
  ok(`準備：${dA} に高2の授業、${dB} に高1の授業、高2・高1の生徒`);

  // 欠席の連絡
  const cls = (await student(S2, "classes")).classes.find(c => c.class_date === dA);
  assert.ok(cls?.can_register, "高2の授業が出て、連絡できる");
  assert.ok(!(await student(S2, "classes")).classes.some(c => c.class_date === dB), "高1の授業は出ない");
  const { id: absenceId } = await student(S2, "absence", { date: dA, type: "高2授業", reason: "E2E" });
  await rejects(student(S2, "absence", { date: dA, type: "高2授業" }), /すでに欠席/, "二重の連絡");
  await rejects(student(S1, "absence", { date: dA, type: "高2授業" }), /自分の学年/, "ほかの学年の授業");
  let mk = await student(S2, "makeup");
  assert.equal(mk.credits.filter(c => c.status === "available").length, 1);
  ok("欠席の連絡：ストックが1つ付く・二重とほかの学年は不可");

  // 振替の申請 → 承認
  const opt = (await student(S2, "makeup_options")).options.find(o => o.class_date === dB);
  assert.ok(opt && opt.class_type === "高1授業" && opt.remaining > 0, "高1の授業が候補に出る");
  const { id: reqId } = await student(S2, "makeup_request", { date: dB, type: "高1授業" });
  await rejects(student(S2, "absence_cancel", { id: absenceId }), /振替の申請に使われています/, "使用中の欠席の取り消し");
  const pend = await rest("GET", `makeup_requests?select=status&id=eq.${reqId}`);
  assert.equal(pend[0].status, "pending");
  await rpc("admin_approve_makeup", { p_request_id: reqId });
  mk = await student(S2, "makeup");
  assert.equal(mk.requests.find(r => r.id === reqId).status, "approved");
  assert.equal(mk.credits[0].status, "used");
  ok("振替の申請 → 管理者の承認：ストックは使用済み");

  // 生徒の取り消し → ストックが戻る → 欠席も取り消せる
  await student(S2, "makeup_cancel", { id: reqId });
  mk = await student(S2, "makeup");
  assert.equal(mk.credits[0].status, "available");
  await student(S2, "absence_cancel", { id: absenceId });
  mk = await student(S2, "makeup");
  assert.equal(mk.credits.filter(c => c.status === "available").length, 0);
  ok("取り消し：振替の取り消しでストックが戻り、欠席の取り消しでストックも消える");

  // 権限
  const saved = token; token = null;
  await rejects(rest("GET", "class_absences?select=id&limit=1"), /permission denied/, "anon で欠席を読む");
  await rejects(rpc("admin_approve_makeup", { p_request_id: reqId }, false), /permission denied/, "anon で承認");
  token = saved;
  ok("権限：ログインなしでは欠席を読めず、承認もできない");
}

try {
  await main();
  console.log(`\n${passed} 項目すべて成功`);
} catch (e) {
  console.error("\n✘ 失敗:", e.message);
  process.exitCode = 1;
} finally {
  if (token) {
    try { await cleanup(); console.log("テストデータを消しました"); }
    catch (e) { console.error("テストデータの削除に失敗しました:", e.message); process.exitCode = 1; }
  }
}
