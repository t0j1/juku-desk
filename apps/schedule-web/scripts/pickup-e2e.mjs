// 送迎予約の通しのテスト（開発用 Supabase に対して実際に行う）。
// 生徒2人の登録 → 予約 → 管理者の相乗り打診 → 2人の回答 → 確定 までを、本物の DB・Edge Function・権限で確かめる。
// 作ったテストデータ（名前が「E2Eテスト」で始まる生徒と、その予約・便）は、最後に消す（途中で失敗しても消す）。
//
// 準備: リポジトリ直下に .env.dev を作り、開発用プロジェクトの管理者を書く（Git には入りません）
//   ADMIN_EMAIL=...
//   ADMIN_PASSWORD=...
// 実行: node scripts/pickup-e2e.mjs
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const root = new URL("../", import.meta.url);
const read = p => readFileSync(new URL(p, root), "utf8");

// 接続先は config.js の dev を使う。本番には絶対につながない
const cfg = read("public/js/config.js");
const dev = cfg.match(/dev:\s*\{\s*url:\s*"([^"]+)",\s*key:\s*"([^"]+)"/);
if (!dev) throw new Error("config.js から開発用の接続先を読めません");
const [, URL_, KEY] = dev;
const prod = cfg.match(/prod:\s*\{\s*url:\s*"([^"]+)"/)?.[1];
if (URL_ === prod) throw new Error("開発用と本番の接続先が同じです。中止します");

let env = {};
try {
  env = Object.fromEntries(read(".env.dev").split(/\r?\n/).filter(l => /^\s*[A-Z_]+\s*=/.test(l))
    .map(l => { const i = l.indexOf("="); return [l.slice(0, i).trim(), l.slice(i + 1).trim().replace(/^["']|["']$/g, "")]; }));
} catch { /* 無ければ環境変数から */ }
const ADMIN_EMAIL = process.env.ADMIN_EMAIL || env.ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.ADMIN_PASSWORD || env.ADMIN_PASSWORD;
if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
  console.error("管理者のメールアドレスとパスワードを .env.dev に書いてください（ADMIN_EMAIL= / ADMIN_PASSWORD=）");
  process.exit(2);
}

const { suggestTime } = vm.runInNewContext(`${read("public/js/common.js")}\n${read("public/js/pickup-common.js")}\n;({ suggestTime })`, {});
const PREFIX = "E2Eテスト";
const STUDENTS = [{ name: `${PREFIX}1`, email: "e2e-1@example.test" }, { name: `${PREFIX}2`, email: "e2e-2@example.test" }];

// ---- 通信 ----
let token = null;
async function http(method, path, { body, auth = true, prefer } = {}) {
  const res = await fetch(URL_ + path, {
    method,
    headers: {
      apikey: KEY, "Content-Type": "application/json",
      ...(auth && token ? { Authorization: `Bearer ${token}` } : {}),
      ...(prefer ? { Prefer: prefer } : {}),
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : null;
  if (!res.ok) { const e = new Error(`${method} ${path} → ${res.status} ${data?.message || data?.error || text}`); e.status = res.status; e.body = data; throw e; }
  return data;
}
const rest = (method, path, body) => http(method, `/rest/v1/${path}`, { body, prefer: "return=representation" });
const rpc = (fn, args, auth = true) => http("POST", `/rest/v1/rpc/${fn}`, { body: args, auth });
const student = (s, action, params = {}) => http("POST", "/functions/v1/pickup-api", { body: { action, email: s.email, ...params }, auth: false });
const api = (action, params = {}) => http("POST", "/functions/v1/pickup-api", { body: { action, ...params }, auth: false });

let passed = 0;
const ok = label => { passed++; console.log("  ✔", label); };
async function rejects(promise, re, label) {
  try { await promise; } catch (e) { assert.match(String(e.body?.error || e.message), re, `${label}: ${e.message}`); return; }
  assert.fail(`${label}: 失敗するはずが成功した`);
}

// ---- 後片付け（前回の残りも含めて、テスト用の生徒とその予約・便を消す） ----
async function cleanup() {
  const ss = await rest("GET", `students?select=id&name=like.${encodeURIComponent(PREFIX + "*")}`);
  if (!ss.length) return 0;
  const ids = ss.map(s => s.id).join(",");
  const res = await rest("GET", `pickup_reservations?select=id,group_id&student_id=in.(${ids})`);
  const groups = [...new Set(res.map(r => r.group_id).filter(Boolean))];
  if (res.length) await rest("DELETE", `pickup_reservations?student_id=in.(${ids})`);   // 打診は予約と一緒に消える
  if (groups.length) await rest("DELETE", `pickup_groups?id=in.(${groups.join(",")})`);
  await rest("DELETE", `students?id=in.(${ids})`);                                      // 連絡先・登録コードも一緒に消える
  return ss.length;
}

// 15分違いの2つの時刻が空いている日を探す（今日の翌日から）
async function findDate() {
  const info = await rpc("get_pickup_info", {}, false);
  for (let i = 1; i <= 30; i++) {
    const d = new Date(`${info.today}T00:00:00Z`); d.setUTCDate(d.getUTCDate() + i);
    const day = d.toISOString().slice(0, 10);
    if (day > info.max_date) break;
    const slots = await rpc("get_pickup_slots", { p_date: day }, false);
    const open = new Map(slots.filter(s => s.remaining > 0 && !s.is_group).map(s => [s.slot, s]));
    for (const s of open.values()) {
      const [h, m] = s.slot.split(":").map(Number), t2 = `${String(h + Math.floor((m + 15) / 60)).padStart(2, "0")}:${String((m + 15) % 60).padStart(2, "0")}`;
      if (open.has(t2)) return { day, t1: s.slot, t2 };
    }
  }
  throw new Error("30日以内に、15分違いで空いている時刻が見つかりません。管理画面の「送迎設定」で送迎時間帯を登録してください。");
}

async function main() {
  console.log(`接続先: ${URL_}（開発用）`);
  const auth = await http("POST", "/auth/v1/token?grant_type=password", { body: { email: ADMIN_EMAIL, password: ADMIN_PASSWORD }, auth: false });
  token = auth.access_token;
  const left = await cleanup();
  if (left) console.log(`  （前回のテストデータ ${left} 人分を消しました）`);

  // 1. 生徒2人を作り、登録コードを発行
  for (const s of STUDENTS) {
    [s.row] = await rest("POST", "students", { name: s.name, grade: "高2", phone: "000-0000-0000" });
    s.code = await rpc("issue_link_code", { p_student_id: s.row.id });
  }
  ok("管理者：生徒2人の登録と登録コードの発行");

  // 2. 登録コードで結び付け
  for (const s of STUDENTS) {
    assert.deepEqual(await student(s, "me"), { linked: false });
    const r = await student(s, "link", { code: s.code });
    assert.equal(r.student_name, s.name);
    assert.equal((await student(s, "me")).student_name, s.name);
  }
  await rejects(student({ email: "e2e-x@example.test" }, "link", { code: STUDENTS[0].code }), /登録コード/, "使用済みのコード");
  ok("生徒：登録コードで結び付け（コードは1回だけ）");

  // 3. 15分違いで予約
  const { day, t1, t2 } = await findDate();
  const [A, B] = STUDENTS;
  A.res = (await student(A, "submit", { date: day, time: t1, notes: "E2E", party_size: 2 })).id;   // A は2名で予約
  B.res = (await student(B, "submit", { date: day, time: t2 })).id;
  await rejects(student(A, "submit", { date: day, time: t2 }), /すでに予約/, "同じ日の2件目");
  const pend = await rest("GET", `pickup_reservations?select=id,status,group_id&id=in.(${A.res},${B.res})`);
  assert.ok(pend.every(r => r.status === "pending" && !r.group_id));
  assert.equal((await student(A, "mine")).reservations.find(r => r.id === A.res).party_size, 2);
  ok(`生徒：${day} ${t1}（2名）と ${t2}（1名）で予約（未承認）`);

  // 4. 他人の予約は取り消せない・anon ではテーブルを読めない
  await rejects(student(A, "cancel", { id: B.res }), /取り消せません/, "他人の予約の取り消し");
  const saved = token; token = null;
  await rejects(rest("GET", "pickup_reservations?select=id&limit=1"), /permission denied/, "anon で予約を読む");
  token = saved;
  ok("権限：他人の予約は取り消せない・ログインなしでは予約を読めない");

  // 5. 管理者：共通時刻を提案して打診
  const [ps] = await rest("GET", "pickup_settings?select=*&id=eq.1");
  const sg = suggestTime([t1, t2], { tolerance: ps.tolerance_minutes, step: 5, trip: ps.trip_minutes });
  assert.ok(sg.best, "共通時刻の候補がある");
  const props = await rpc("admin_propose_carpool", { p_reservation_ids: [A.res, B.res], p_time: sg.best, p_group: null });
  const byRes = new Map(props.map(p => [p.reservation_id, p]));
  ok(`管理者：${sg.best} 発で相乗りを打診（候補 ${sg.candidates.join("・")}）`);

  // 6. 回答：A は「自分の予約」から、B は回答リンクから
  const mineA = (await student(A, "mine")).reservations.find(r => r.id === A.res);
  assert.equal(mineA.proposed_time, sg.best);
  await rejects(student(B, "respond", { proposal_id: mineA.proposal_id, accept: true }), /回答できません/, "他人の打診への回答");
  const tokB = byRes.get(B.res).token;   // 提案時刻が B の希望と同じなら、B には打診しない（最初から承認扱い）
  if (byRes.get(A.res).token) {
    const first = await student(A, "respond", { proposal_id: mineA.proposal_id, accept: true });
    assert.equal(first.group_status, tokB ? "proposing" : "confirmed", tokB ? "1人目の回答ではまだ確定しない" : "B は最初から承認なので確定");
  }
  if (tokB) {
    const view = (await api("proposal", { token: tokB })).proposal;
    assert.equal(view.proposed_time, sg.best); assert.equal(view.response, "waiting");
    assert.equal((await api("respond_token", { token: tokB, accept: true })).group_status, "confirmed");
    await rejects(api("respond_token", { token: tokB, accept: false }), /回答できません/, "二重回答");
  }
  ok("生徒：1人目は「自分の予約」から、2人目は回答リンクから承認 → 確定");

  // 7. 確定の確認
  for (const s of STUDENTS) {
    const r = (await student(s, "mine")).reservations.find(x => x.id === s.res);
    assert.equal(r.status, "approved"); assert.equal(r.approved_time, sg.best);
  }
  const [grp] = await rest("GET", `pickup_groups?select=status,approved_time,max_capacity&id=eq.${(await rest("GET", `pickup_reservations?select=group_id&id=eq.${A.res}`))[0].group_id}`);
  assert.equal(grp.status, "confirmed"); assert.equal(grp.approved_time.slice(0, 5), sg.best);
  const slot = (await rpc("get_pickup_slots", { p_date: day }, false)).find(s => s.slot === sg.best);
  if (slot) { assert.equal(slot.is_group, true); assert.equal(slot.remaining, Math.max(grp.max_capacity - 3, 0)); }
  ok(`確定：2人とも ${sg.best} 発で承認、乗車は合計3名（予約フォームの残りは ${Math.max(grp.max_capacity - 3, 0)}名）`);

  // 8. 取り消し → 1人になっても便は残る → 2人とも取り消すと便も取り消し
  await student(A, "cancel", { id: A.res });
  assert.equal((await rest("GET", `pickup_groups?select=status&approved_time=eq.${sg.best}&pickup_date=eq.${day}&status=neq.cancelled`)).length, 1);
  await student(B, "cancel", { id: B.res });
  assert.equal((await rest("GET", `pickup_groups?select=status&approved_time=eq.${sg.best}&pickup_date=eq.${day}&status=neq.cancelled`)).length, 0);
  ok("取り消し：誰もいなくなった便は自動で取り消し");
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
    catch (e) { console.error("テストデータの削除に失敗しました（管理画面の「生徒」タブで「E2Eテスト」を確認してください）:", e.message); process.exitCode = 1; }
  }
}
