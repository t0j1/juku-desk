// supabase/pickup.sql のテスト。PGlite（WASM の Postgres）に Supabase の最小限の模擬を作り、
// schema.sql → pickup.sql（2回）を流してから、予約・承認・相乗り・取り消し・期限切れを確かめる。
// 実行: npm i --no-save @electric-sql/pglite && node scripts/pickup-db.test.mjs
import { PGlite } from "@electric-sql/pglite";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const REPO = new URL("../supabase/", import.meta.url).pathname;
const db = new PGlite();
const ADMIN = "11111111-1111-1111-1111-111111111111";
const OTHER = "22222222-2222-2222-2222-222222222222";

// ---- Supabase の最小限の模擬 ----
await db.exec(`
  create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
  grant usage on schema public to anon, authenticated, service_role;
  create schema auth; grant usage on schema auth to anon, authenticated, service_role;
  create table auth.users (id uuid primary key);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  grant execute on function auth.uid() to anon, authenticated, service_role;
  insert into auth.users values ('${ADMIN}'), ('${OTHER}');
`);
await db.exec(readFileSync(REPO + "schema.sql", "utf8"));
await db.exec(`insert into public.admins values ('${ADMIN}')`);
await db.exec(readFileSync(REPO + "pickup.sql", "utf8"));
await db.exec(readFileSync(REPO + "pickup.sql", "utf8"));   // 2回目も壊れないこと
// service_role はテーブルの全権限を持つ（Supabase の既定）
await db.exec(`grant all on all tables in schema public to service_role;`);

async function as(role, sub, sql, params) {
  await db.exec(`reset role; select set_config('request.jwt.claim.sub', '${sub || ""}', false); set role ${role};`);
  try { return (await db.query(sql, params)).rows; } finally { await db.exec("reset role"); }
}
const admin = (sql, p) => as("authenticated", ADMIN, sql, p);
const svc = (sql, p) => as("service_role", "", sql, p);
async function fails(promise, re, label) {
  try { await promise; } catch (e) { assert.match(e.message, re, `${label}: ${e.message}`); return e; }
  assert.fail(`${label}: 失敗するはずが成功した`);
}
let passed = 0;
const ok = label => { passed++; console.log("  ✔", label); };

// 日本時間の明日・明後日
const [{ d1, d2, d3 }] = (await db.query(`select (pickup_now()::date + 1)::text d1, (pickup_now()::date + 2)::text d2, (pickup_now()::date + 3)::text d3`)).rows;

// ---- 権限 ----
await fails(as("anon", "", "select * from pickup_reservations"), /permission denied/, "anon は予約を読めない");
await fails(as("anon", "", "select * from students"), /permission denied/, "anon は生徒を読めない");
await fails(as("anon", "", `select submit_pickup_reservation(gen_random_uuid(), '${d1}', '17:00', '')`), /permission denied/, "anon は予約関数を呼べない");
await fails(as("anon", "", `select * from link_student('X', 'U1', null)`), /permission denied/, "anon は結び付け関数を呼べない");
await fails(as("authenticated", OTHER, `select submit_pickup_reservation(gen_random_uuid(), '${d1}', '17:00', '')`), /permission denied/, "ログインユーザーも予約関数は呼べない");
assert.equal((await as("authenticated", OTHER, "select * from pickup_settings")).length, 0);
await fails(as("authenticated", OTHER, "insert into students (name) values ('x')"), /row-level security/, "管理者以外は生徒を登録できない");
await fails(as("authenticated", OTHER, `select issue_link_code(gen_random_uuid())`), /管理者のみ/, "管理者以外はコードを発行できない");
ok("権限：anon・管理者以外は送迎データに触れない");

// ---- 設定 ----
for (let dow = 0; dow < 7; dow++)
  await admin(`insert into pickup_availability (day_of_week, start_time, end_time, max_capacity) values ($1, '16:00', '21:00', 3)`, [dow]);
await fails(admin(`insert into pickup_availability (day_of_week, start_time, end_time) values (1, '20:00', '22:00')`), /重なる/, "時間帯の重なり");
ok("送迎時間帯の登録と重なりの拒否");

const anonSlots = async d => as("anon", "", `select * from get_pickup_slots($1)`, [d]);
let slots = await anonSlots(d1);
assert.equal(slots[0].slot, "16:00"); assert.equal(slots.at(-1).slot, "20:45"); assert.equal(slots.length, 20);
assert.ok(slots.every(s => s.remaining === 3 && !s.is_group));
const info = (await as("anon", "", "select get_pickup_info() i"))[0].i;
assert.equal(info.place, "勝瑞駅"); assert.equal(info.days.length, 7);
ok("選べる時刻：16:00〜20:45（最終便は21:00に戻れる時刻）、anon から取得できる");

// ---- 生徒と登録コード ----
const names = ["A", "B", "C", "D", "E", "F", "G", "H"];
const sid = {}, cid = {};
for (const n of names) sid[n] = (await admin(`insert into students (name, grade) values ($1, '高2') returning id`, [n]))[0].id;
for (const n of names) {
  const code = (await admin(`select issue_link_code($1) c`, [sid[n]]))[0].c;
  assert.match(code, /^[A-HJ-NP-Z2-9]{8}$/);
  cid[n] = (await svc(`select * from link_student($1, $2, null, $3)`, [code.toLowerCase().replace(/(....)/, "$1-"), "U" + n, n]))[0].contact_id;
  if (n === "A") await fails(svc(`select * from link_student($1, 'Uzz', null)`, [code]), /登録コード/, "コードは1回だけ");
}
await fails(svc(`select * from link_student('AAAAAAAA', 'Uzz', null)`), /登録コード/, "間違ったコード");
assert.equal((await svc(`select * from find_contact('UA', null)`))[0].student_name, "A");
// 再発行 → 結び付け直すと、前の LINE は無効
const code2 = (await admin(`select issue_link_code($1) c`, [sid.H]))[0].c;
const newH = (await svc(`select * from link_student($1, 'UH2', null)`, [code2]))[0].contact_id;
await fails(svc(`select submit_pickup_reservation($1, $2, '16:00')`, [cid.H, d1]), /生徒の登録が確認できません/, "古い LINE では予約できない");
cid.H = newH;
ok("登録コード：8文字・1回限り・ハイフンや小文字も可・再発行で前の結び付けは無効");

// ---- 予約 ----
const submit = (n, d, t, notes = "") => svc(`select submit_pickup_reservation($1, $2, $3, $4) id`, [cid[n], d, t, notes]).then(r => r[0].id);
const rid = {};
rid.A = await submit("A", d1, "17:00");
rid.B = await submit("B", d1, "17:15");
await fails(submit("A", d1, "18:00"), /すでに予約/, "同じ日に2件");
await fails(submit("C", d1, "17:05"), /予約できません/, "刻みに合わない時刻");
await fails(submit("C", d1, "20:50"), /予約できません/, "最終便より後");
const [{ d_over: over }] = (await db.query(`select ($1::date + 1)::text d_over`, [info.max_date])).rows;
await fails(submit("C", over, "17:00"), /予約できません/, "受付範囲（60日先）より後");
rid.E = await submit("E", d2, "18:00"); rid.F = await submit("F", d2, "18:00"); rid.G = await submit("G", d2, "18:00");
await fails(submit("H", d2, "18:00"), /満席/, "定員3を超える");
assert.equal((await anonSlots(d2)).find(s => s.slot === "18:00").remaining, 0);
ok("予約：定員・1日1件・刻み・最終便・受付範囲のチェック");

// 休講の日は出ない
await admin(`insert into events (event_date, type, is_published) values ($1, '休講', true)`, [d3]);
assert.equal((await anonSlots(d3)).length, 0);
await fails(submit("H", d3, "17:00"), /予約できません/, "休講日");
ok("公開済みの「休講」の日は予約できない");

// ---- 承認・車1台 ----
// C は 19:00 希望 → 19:05 に時刻を直して承認
rid.C = await submit("C", d1, "19:00");
const gC = (await admin(`select admin_approve_reservation($1, '19:05') g`, [rid.C]))[0].g;
slots = await anonSlots(d1);
assert.ok(!slots.some(s => s.slot === "19:00" || s.slot === "19:15"), "19:05 の便と重なる 19:00・19:15 は出ない");
assert.ok(!slots.some(s => s.slot === "19:05"), "刻み外の便の時刻は選択肢に出さない（管理者が入れる）");
rid.D = await submit("D", d1, "19:30");
await fails(admin(`select admin_approve_reservation($1, '19:10')`, [rid.D]), /19:05 の便と時間が重なります/, "車1台");
await admin(`select admin_approve_reservation($1, null, $2)`, [rid.D, gC]);   // 19:05 の便に相乗り
let r = (await admin(`select status, approved_time::text t from pickup_reservations where id = $1`, [rid.D]))[0];
assert.deepEqual(r, { status: "approved", t: "19:05:00" });
await fails(admin(`update pickup_reservations set status = 'pending' where id = $1`, [rid.D]), /変えることはできません/, "approved → pending");
ok("承認：時刻の変更・既存の便への追加・便の重なりの拒否・状態遷移の制限");

// ---- 相乗り調整（17:00 と 17:15 → 17:10） ----
const props = await admin(`select * from admin_propose_carpool(array[$1, $2]::uuid[], '17:10')`, [rid.A, rid.B]);
assert.equal(props.length, 2); assert.ok(props.every(p => p.token && p.token.length === 64));
const tokA = props.find(p => p.reservation_id === rid.A).token, tokB = props.find(p => p.reservation_id === rid.B).token;
const view = (await svc(`select * from get_pickup_proposal_by_token($1)`, [tokA]))[0];
assert.equal(view.proposed_time, "17:10"); assert.equal(view.pickup_time, "17:00"); assert.equal(view.response, "waiting");
slots = await anonSlots(d1);
assert.ok(!slots.some(s => s.slot === "17:00" || s.slot === "17:15"), "調整中の便も車の時間を押さえる");
assert.equal((await svc(`select respond_pickup_proposal_by_token($1, true) s`, [tokA]))[0].s, "proposing");
await fails(svc(`select respond_pickup_proposal_by_token($1, false)`, [tokA]), /回答できません/, "二重回答");
const mine = await svc(`select * from my_pickup_reservations($1)`, [cid.B]);
assert.equal(mine[0].proposed_time, "17:10");
await fails(svc(`select respond_pickup_proposal($1, $2, true)`, [cid.E, mine[0].proposal_id]), /回答できません/, "他人の打診には回答できない");
assert.equal((await svc(`select respond_pickup_proposal($1, $2, true) s`, [cid.B, mine[0].proposal_id]))[0].s, "confirmed");
const ab = await admin(`select status, approved_time::text t from pickup_reservations where id in ($1, $2)`, [rid.A, rid.B]);
assert.ok(ab.every(x => x.status === "approved" && x.t === "17:10:00"));
ok("相乗り：17:00＋17:15 → 17:10 を打診、全員承認で自動確定");

// ---- 辞退 → 辞退者を外して確定 ----
const pEFG = await admin(`select * from admin_propose_carpool(array[$1, $2, $3]::uuid[], '18:00')`, [rid.E, rid.F, rid.G]);
assert.ok(pEFG.every(p => p.token === null), "希望時刻どおりの人にはトークンなし（最初から承認）");
let st = await admin(`select distinct status from pickup_reservations where id = any($1::uuid[])`, [[rid.E, rid.F, rid.G]]);
assert.deepEqual(st, [{ status: "approved" }]);
ok("相乗り：全員が希望時刻どおりなら、その場で確定");

// 別の日で辞退のケース
const d4 = (await db.query(`select (pickup_now()::date + 5)::text d`)).rows[0].d;
const x1 = await submit("E", d4, "17:00"), x2 = await submit("F", d4, "17:30"), x3 = await submit("G", d4, "17:15");
const p3 = await admin(`select * from admin_propose_carpool(array[$1, $2, $3]::uuid[], '17:15')`, [x1, x2, x3]);
const g3 = (await admin(`select group_id from pickup_reservations where id = $1`, [x1]))[0].group_id;
await svc(`select respond_pickup_proposal_by_token($1, true)`, [p3.find(p => p.reservation_id === x1).token]);
await svc(`select respond_pickup_proposal_by_token($1, false)`, [p3.find(p => p.reservation_id === x2).token]);
assert.equal((await admin(`select status from pickup_groups where id = $1`, [g3]))[0].status, "proposing");
assert.equal((await admin(`select admin_resolve_group($1, 'drop_declined') s`, [g3]))[0].s, "confirmed");
r = await admin(`select id, status, group_id from pickup_reservations where id = any($1::uuid[]) order by pickup_time`, [[x1, x2, x3]]);
assert.equal(r.find(x => x.id === x2).status, "pending"); assert.equal(r.find(x => x.id === x2).group_id, null);
assert.ok(r.filter(x => x.id !== x2).every(x => x.status === "approved"));
ok("相乗り：辞退があれば調整中のまま → 辞退者を外すと、残りで確定");

// 調整をやめる / 電話で確認済み
const y1 = await submit("A", d4, "18:30"), y2 = await submit("B", d4, "18:45");
await admin(`select * from admin_propose_carpool(array[$1, $2]::uuid[], '18:40')`, [y1, y2]);
const gy = (await admin(`select group_id from pickup_reservations where id = $1`, [y1]))[0].group_id;
assert.equal((await admin(`select admin_resolve_group($1, 'cancel') s`, [gy]))[0].s, "cancelled");
assert.ok((await anonSlots(d4)).some(s => s.slot === "18:30"), "取りやめた便の時間は空く");
await admin(`select * from admin_propose_carpool(array[$1, $2]::uuid[], '18:40')`, [y1, y2]);
const gy2 = (await admin(`select group_id from pickup_reservations where id = $1`, [y1]))[0].group_id;
assert.equal((await admin(`select admin_resolve_group($1, 'confirm_all') s`, [gy2]))[0].s, "confirmed");
ok("相乗り：調整の取りやめ・再提案・電話で確認済みとして確定");

// ---- 利用者の取り消し → 最後の1人なら便も取り消し ----
await svc(`select cancel_pickup_reservation($1, $2)`, [cid.C, rid.C]);
assert.equal((await admin(`select status from pickup_groups where id = $1`, [gC]))[0].status, "confirmed", "D が残っている");
await svc(`select cancel_pickup_reservation($1, $2)`, [cid.D, rid.D]);
assert.equal((await admin(`select status from pickup_groups where id = $1`, [gC]))[0].status, "cancelled");
await fails(svc(`select cancel_pickup_reservation($1, $2)`, [cid.D, rid.D]), /取り消せません/, "二重取り消し");
await fails(svc(`select cancel_pickup_reservation($1, $2)`, [cid.E, rid.A]), /取り消せません/, "他人の予約");
ok("取り消し：本人だけ・誰もいなくなった便は自動で取り消し");

// ---- 期限切れ ----
const today = (await db.query(`select pickup_now()::date::text d`)).rows[0].d;
await db.exec(`insert into pickup_reservations (student_id, pickup_date, pickup_time) values ('${sid.H}', '${today}', '00:00')`);
await fails(svc(`select submit_pickup_reservation($1, $2, '00:00')`, [cid.H, today]), /./, "過去の時刻は予約できない");
const n = (await svc(`select expire_pickups() n`))[0].n;
assert.equal(n, 1);
r = (await admin(`select status, reject_reason from pickup_reservations where student_id = $1 and pickup_date = $2`, [sid.H, today]))[0];
assert.deepEqual(r, { status: "rejected", reject_reason: "期限切れ" });
ok("期限切れ：承認されないまま時刻を過ぎた予約は却下（期限切れ）");

// ---- 変更履歴 ----
const logs = (await admin(`select table_name, count(*)::int c from audit_log group by 1 order by 1`));
assert.ok(logs.some(l => l.table_name === "pickup_reservations") && logs.some(l => l.table_name === "students"));
ok("変更履歴に送迎・生徒の変更が残る");

console.log(`\n${passed} 項目すべて成功`);
