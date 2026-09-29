// supabase/absence.sql（欠席連絡・振替授業）のテスト。PGlite（WASM の Postgres）に Supabase の最小限の模擬を作り、
// schema.sql → pickup.sql → absence.sql（absence.sql は2回）を流してから、欠席・ストック・振替の申請と承認を確かめる。
// 実行: npm i --no-save @electric-sql/pglite && node scripts/absence-db.test.mjs
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const SQL = f => readFileSync(new URL(`../supabase/${f}`, import.meta.url), "utf8");
const db = new PGlite();
const ADMIN = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";

await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
  grant usage on schema public to anon, authenticated, service_role;
  create schema auth; grant usage on schema auth to anon, authenticated, service_role;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant execute on function auth.uid() to anon, authenticated, service_role;
  insert into auth.users values ('${ADMIN}'), ('${OTHER}');
`);
await db.exec(SQL("schema.sql"));
await db.exec(`insert into public.admins values ('${ADMIN}')`);
await db.exec(SQL("pickup.sql"));
await db.exec(SQL("absence.sql"));
await db.exec(SQL("absence.sql"));   // 2回目も壊れないこと
await db.exec(`grant all on all tables in schema public to service_role;`);

async function as(role, sub, sql, params) {
  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '${sub || ""}', false); set role ${role};`);
  try { return (await db.query(sql, params)).rows; } finally { await db.exec("reset role"); }
}
const admin = (sql, p) => as("authenticated", ADMIN, sql, p);
const svc = (sql, p) => as("service_role", "", sql, p);
async function fails(promise, re, label) {
  try { await promise; } catch (e) { assert.match(e.message, re, `${label}: ${e.message}`); return; }
  assert.fail(`${label}: 失敗するはずが成功した`);
}
let passed = 0;
const ok = label => { passed++; console.log("  ✔", label); };

const ymdOf = v => (v instanceof Date ? v.toISOString().slice(0, 10) : v);   // PGlite は date を Date で返す
const day = n => db.query(`select (pickup_now()::date + $1::int)::text d`, [n]).then(r => r.rows[0].d);
const [today, d1, d2, d3, d4, d5, d6] = await Promise.all([0, 1, 2, 3, 4, 5, 6].map(day));

// ---- 見本の授業 ----
const ev = (d, type, start = "18:30", pub = true) =>
  admin(`insert into events (event_date, type, title, start_time, end_time, is_published) values ($1, $2, $2, $3, '21:40', $4)`, [d, type, start, pub]);
await ev(d1, "高1授業"); await ev(d4, "高1授業"); await ev(d2, "高1授業");
await ev(d2, "高2授業"); await ev(d5, "高2授業");
await ev(d3, "高3授業"); await ev(d6, "高3授業");
await ev(today, "高2授業", "00:00");            // 今日の 0:00 開始＝もう始まっている
await ev(d6, "高2授業", "18:30", false);         // 下書きは対象外
await admin(`insert into events (event_date, type, is_published) values ($1, '休講', true)`, [d5]);   // d5 は休講

// ---- 生徒（高1・高2・高3・学年なし）と連絡先 ----
const sid = {}, cid = {};
for (const [k, grade] of [["T1", "高1"], ["T2", "高2"], ["T3", "高3"], ["TX", ""]]) {
  sid[k] = (await admin(`insert into students (name, grade) values ($1, $2) returning id`, [k, grade]))[0].id;
  const code = (await admin(`select issue_link_code($1) c`, [sid[k]]))[0].c;
  cid[k] = (await svc(`select * from link_student($1, $2, null)`, [code, "U" + k]))[0].contact_id;
}

// ---- 権限 ----
for (const t of ["class_absences", "makeup_credits", "makeup_requests", "makeup_settings"]) {
  await fails(as("anon", "", `select * from ${t}`), /permission denied/, `anon は ${t} を読めない`);
}
await fails(as("anon", "", `select * from my_classes($1)`, [cid.T2]), /permission denied/, "anon は生徒の関数を呼べない");
await fails(as("authenticated", OTHER, `select * from my_classes($1)`, [cid.T2]), /permission denied/, "ログインユーザーも生徒の関数は呼べない");
await fails(as("authenticated", OTHER, `select admin_grant_credit($1, '')`, [sid.T2]), /管理者のみ/, "管理者以外はストックを足せない");
assert.equal((await as("authenticated", OTHER, "select * from makeup_credits")).length, 0);
ok("権限：anon・管理者以外は欠席・振替のデータに触れない");

// ---- 自分の授業 ----
let cls = await svc(`select * from my_classes($1)`, [cid.T2]);
assert.deepEqual(cls.map(c => [ymdOf(c.class_date), c.class_type]), [[today, "高2授業"], [d2, "高2授業"]], "高2の授業だけ・休講日と下書きは除く");
assert.equal(cls[0].can_register, false, "始まった授業は連絡できない");
assert.equal(cls[1].can_register, true);
await fails(svc(`select * from my_classes($1)`, [cid.TX]), /学年が登録されていない/, "学年なし");
ok("自分の授業：自分の学年だけ・休講日と下書きは除く・始まった授業は連絡できない");

// ---- 欠席の連絡 → ストック ----
const absence = (k, d, type, reason = "") => svc(`select register_absence($1, $2, $3, $4) id`, [cid[k], d, type, reason]).then(r => r[0].id);
const a2 = await absence("T2", d2, "高2授業", "体調不良");
let cr = await admin(`select status, granted_on::text g, expires_on::text e from makeup_credits where absence_id = $1`, [a2]);
const [{ exp }] = (await db.query(`select (($1::date + interval '3 months')::date)::text exp`, [d2])).rows;
assert.deepEqual(cr, [{ status: "available", g: d2, e: exp }], "ストックの期限は欠席した日から3か月");
await fails(absence("T2", d2, "高2授業"), /すでに欠席/, "二重の連絡");
await fails(absence("T2", d1, "高1授業"), /自分の学年/, "ほかの学年の授業");
await fails(absence("T2", today, "高2授業"), /開始時刻を過ぎている/, "始まった授業");
await fails(absence("T2", d5, "高2授業"), /見つかりません/, "休講の日");
await fails(absence("T2", d4, "高2授業"), /見つかりません/, "授業のない日");
cls = await svc(`select * from my_classes($1)`, [cid.T2]);
assert.equal(cls[1].absence_id, a2); assert.equal(cls[1].can_cancel, true); assert.equal(cls[1].reason, "体調不良");
ok("欠席の連絡：ストックが1つ付く（3か月）・二重・ほかの学年・開始後・休講日は不可");

// ---- 振替に申請できる授業 ----
let opts = await svc(`select * from makeup_options($1)`, [cid.T2]);
assert.ok(opts.length > 0 && opts.every(o => o.class_type !== "高2授業"), "違う学年の授業だけ");
assert.ok(opts.every(o => o.remaining === 3 && !o.requested));
assert.deepEqual(await svc(`select * from makeup_options($1)`, [cid.T1]), [], "ストックが無ければ候補なし");
ok("振替の候補：違う学年の授業だけ・残り人数つき・ストックが無ければ空");

// ---- 振替の申請 ----
const request = (k, d, type) => svc(`select request_makeup($1, $2, $3) id`, [cid[k], d, type]).then(r => r[0].id);
await fails(request("T2", d2, "高2授業"), /違う学年/, "同じ学年の授業");
const r1 = await request("T2", d4, "高1授業");
assert.equal((await admin(`select status from makeup_credits where absence_id = $1`, [a2]))[0].status, "reserved");
assert.equal((await svc(`select * from makeup_options($1)`, [cid.T2])).length, 0, "ストックを使い切ったら候補なし");
await fails(request("T2", d3, "高3授業"), /使える振替ストックがありません/, "ストックなし");
await fails(svc(`select cancel_absence($1, $2)`, [cid.T2, a2]), /振替の申請に使われています/, "申請に使っている欠席は取り消せない");
await fails(svc(`select cancel_makeup($1, $2)`, [cid.T1, r1]), /取り消せません/, "他人の申請は取り消せない");
ok("振替の申請：ストックを押さえる・同じ学年やストックなしは不可・使用中の欠席は取り消せない");

// ---- 受け入れ人数 ----
await admin(`update makeup_settings set makeup_capacity = 1 where id = 1`);
const a3 = await absence("T3", d3, "高3授業");
await fails(request("T3", d4, "高1授業"), /いっぱい/, "受け入れ人数");
await admin(`update makeup_settings set makeup_capacity = 3 where id = 1`);
const r3 = await request("T3", d4, "高1授業");
ok("受け入れ人数：申請中＋承認で数える");

// ---- 承認・却下・取り消し ----
await fails(as("authenticated", OTHER, `select admin_approve_makeup($1)`, [r1]), /管理者のみ/, "管理者以外は承認できない");
await admin(`select admin_approve_makeup($1)`, [r1]);
assert.equal((await admin(`select status from makeup_credits where absence_id = $1`, [a2]))[0].status, "used");
await fails(admin(`select admin_approve_makeup($1)`, [r1]), /申請中の振替だけ/, "二重の承認");
await svc(`select cancel_makeup($1, $2)`, [cid.T2, r1]);                         // 承認後でも、開始前なら取り消せる → ストックは戻る
assert.equal((await admin(`select status from makeup_credits where absence_id = $1`, [a2]))[0].status, "available");
const r1b = await request("T2", d3, "高3授業");
await admin(`select admin_reject_makeup($1, '満席のため')`, [r1b]);
assert.equal((await admin(`select status from makeup_credits where absence_id = $1`, [a2]))[0].status, "available", "却下でストックは戻る");
let mm = (await svc(`select my_makeup($1) j`, [cid.T2]))[0].j;
assert.equal(mm.credits.length, 1); assert.equal(mm.credits[0].status, "available"); assert.equal(mm.credits[0].from_type, "高2授業");
assert.deepEqual(mm.requests.map(r => [r.status, r.reject_reason]).sort(), [["cancelled", ""], ["rejected", "満席のため"]]);
// 管理者の取り消し（ストックを戻さない）
await admin(`select admin_approve_makeup($1)`, [r3]);
await admin(`select admin_cancel_makeup($1, false)`, [r3]);
assert.equal((await admin(`select status from makeup_credits where absence_id = $1`, [a3]))[0].status, "used");
ok("承認で使用済み・却下と生徒の取り消しで戻る・管理者の取り消しは戻すかを選べる");

// ---- ストックの期限 ----
await admin(`update makeup_credits set expires_on = $2 where absence_id = $1`, [a2, d2]);   // 期限を d2 に縮める
await fails(request("T2", d3, "高3授業"), /使える振替ストックがありません/, "期限より後の授業");
await admin(`update makeup_credits set expires_on = $2 where absence_id = $1`, [a2, today]);
await admin(`update makeup_credits set expires_on = $2 where absence_id = $1`, [a2, await day(-1)]);
mm = (await svc(`select my_makeup($1) j`, [cid.T2]))[0].j;
assert.equal(mm.credits[0].status, "expired", "期限切れは expired と表示");
assert.deepEqual(await svc(`select * from makeup_options($1)`, [cid.T2]), [], "期限切れのストックでは候補なし");
ok("ストックの期限：振替先の授業の日が期限内でないと使えない・期限切れは expired");

// ---- 欠席の取り消し ----
await admin(`update makeup_credits set expires_on = $2 where absence_id = $1`, [a2, exp]);
await svc(`select cancel_absence($1, $2)`, [cid.T2, a2]);
assert.equal((await admin(`select status from class_absences where id = $1`, [a2]))[0].status, "cancelled");
assert.equal((await admin(`select status from makeup_credits where absence_id = $1`, [a2]))[0].status, "revoked");
await fails(svc(`select cancel_absence($1, $2)`, [cid.T2, a2]), /取り消せません/, "二重の取り消し");
const a2b = await absence("T2", d2, "高2授業");   // 取り消したあと、もう一度連絡できる
assert.ok(a2b);
ok("欠席の取り消し：ストックも消える・もう一度連絡できる");

// ---- 管理者のストックの追加・取り消し ----
const g = (await admin(`select admin_grant_credit($1, '休講の補填') id`, [sid.T1]))[0].id;
assert.equal((await svc(`select * from makeup_options($1)`, [cid.T1])).length > 0, true, "手動のストックで振替できる");
await admin(`select admin_revoke_credit($1, '')`, [g]);
await fails(admin(`select admin_revoke_credit($1, '')`, [g]), /使える状態/, "二重の取り消し");
ok("管理者：ストックの追加（休講の補填など）と取り消し");

// ---- 変更履歴 ----
const logs = await admin(`select distinct table_name from audit_log`);
for (const t of ["class_absences", "makeup_credits", "makeup_requests"]) assert.ok(logs.some(l => l.table_name === t), t);
ok("変更履歴に欠席・ストック・振替の変更が残る");

console.log(`\n${passed} 項目すべて成功`);
