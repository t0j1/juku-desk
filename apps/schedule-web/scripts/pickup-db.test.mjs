// supabase/pickup.sql のテスト。PGlite（WASM の Postgres）に Supabase の最小限の模擬を作り、
// schema.sql → pickup.sql（2回）を流してから、予約・承認・相乗り・取り消し・期限切れを確かめる。
// 実行: npm i --no-save @electric-sql/pglite && node scripts/pickup-db.test.mjs
import { PGlite } from "@electric-sql/pglite";
import { pgcrypto } from "@electric-sql/pglite/contrib/pgcrypto";
import { createHmac, randomBytes } from "node:crypto";
import { readFileSync } from "node:fs";
import assert from "node:assert/strict";

const REPO = new URL("../supabase/", import.meta.url).pathname;
const db = new PGlite({ extensions: { pgcrypto } });
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
  -- pg_net の模擬：送ろうとしたリクエストを記録するだけ（実際の送信は Supabase の pg_net が行う）
  create schema net;
  create table net.calls (id serial primary key, url text, body jsonb, headers jsonb);
  create function net.http_post(url text, body jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000)
    returns bigint language sql as $$ insert into net.calls (url, body, headers) values (url, body, headers) returning id::bigint $$;
  create schema extensions; create extension pgcrypto schema extensions;
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
const [{ d1, d2, d3, n1, n2 }] = (await db.query(`select (pickup_now()::date + 1)::text d1, (pickup_now()::date + 2)::text d2, (pickup_now()::date + 3)::text d3, (pickup_now()::date + 40)::text n1, (pickup_now()::date + 41)::text n2`)).rows;

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

// ---- 人数（定員は人数の合計で数える） ----
const d6 = (await db.query(`select (pickup_now()::date + 6)::text d`)).rows[0].d;
const subN = (n, d, t, size) => svc(`select submit_pickup_reservation($1, $2, $3, '', $4) id`, [cid[n], d, t, size]).then(r => r[0].id);
const remainingAt = async (d, t) => (await anonSlots(d)).find(s => s.slot === t)?.remaining;
const q1 = await subN("A", d6, "17:00", 2);
assert.equal(await remainingAt(d6, "17:00"), 1, "2名の予約で残り1名");
await fails(subN("B", d6, "17:00", 2), /残り1名/, "残りより多い人数");
await fails(subN("B", d6, "17:00", 9), /1〜8名/, "9名");
await fails(subN("B", d6, "17:00", 0), /1〜8名/, "0名");
const q2 = await subN("B", d6, "17:00", 1);
assert.equal(await remainingAt(d6, "17:00"), 0);
await fails(subN("C", d6, "17:00", 1), /満席/, "人数の合計で満席");
assert.equal((await svc(`select * from my_pickup_reservations($1)`, [cid.A])).find(r => r.id === q1).party_size, 2);
// 相乗り：2名＋1名＝3名（定員3）なら確定できる
await admin(`select * from admin_propose_carpool(array[$1, $2]::uuid[], '17:00')`, [q1, q2]);
const gq = (await admin(`select group_id, status from pickup_reservations where id = $1`, [q1]))[0];
assert.equal(gq.status, "approved");
// 満員の便には1名でも入れない
const q3 = await subN("C", d6, "17:30", 1);
await fails(admin(`select admin_approve_reservation($1, null, $2)`, [q3, gq.group_id]), /残り0名/, "満員の便に追加");
// 相乗り：2名＋2名＝4名は定員オーバー
const q4 = await subN("D", d6, "18:00", 2), q5 = await subN("E", d6, "18:15", 2);
await fails(admin(`select * from admin_propose_carpool(array[$1, $2]::uuid[], '18:10')`, [q4, q5]), /合計4名/, "相乗りの定員オーバー");
ok("人数：定員は人数の合計で数える（予約・承認・相乗り）");

// ---- 日付ごとの送迎時間の調整 ----
const d8 = (await db.query(`select (pickup_now()::date + 8)::text d`)).rows[0].d;
const setDay = (mode, windows = [], note = "") => admin(`select admin_set_pickup_day($1, $2, $3::jsonb, $4)`, [d8, mode, JSON.stringify(windows), note]);
await fails(as("authenticated", OTHER, `select admin_set_pickup_day($1, 'closed', '[]'::jsonb, '')`, [d8]), /管理者のみ/, "管理者以外は調整できない");
await fails(as("anon", "", `select * from pickup_windows($1)`, [d8]), /permission denied/, "anon は時間帯の関数を呼べない");
// その日だけ 17:00〜18:00・定員1 → 17:00〜17:45 だけ（最終便は18:00に戻れる時刻）
await setDay("custom", [{ start: "17:00", end: "18:00", capacity: 1 }], "行事のため");
let s8 = await anonSlots(d8);
assert.deepEqual(s8.map(x => x.slot), ["17:00", "17:15", "17:30", "17:45"]);
assert.ok(s8.every(x => x.remaining === 1), "定員はその日の設定（1名）");
await fails(submit("F", d8, "16:00"), /予約できません/, "調整した時間帯の外");
const o1 = await submit("F", d8, "17:15");
await fails(submit("G", d8, "17:15"), /満席/, "その日の定員1");
// 時間帯は複数でき、重なりは拒否
await setDay("custom", [{ start: "16:00", end: "16:30" }, { start: "19:00", end: "19:30" }]);
assert.deepEqual((await anonSlots(d8)).map(x => x.slot), ["16:00", "16:15", "19:00", "19:15"]);
await fails(setDay("custom", [{ start: "16:00", end: "17:00" }, { start: "16:30", end: "17:30" }]), /重なる/, "時間帯の重なり");
await fails(setDay("custom", [{ start: "18:00", end: "17:00" }]), /開始時刻より後/, "終了が開始より前");
await fails(setDay("custom", []), /1つ以上/, "時間帯なし");
// 送迎なし → 選べる時刻なし・予約できない
await setDay("closed", [], "臨時休業");
assert.equal((await anonSlots(d8)).length, 0);
await fails(submit("G", d8, "17:00"), /予約できません/, "送迎なしの日");
// 通常どおりに戻すと、曜日の設定（16:00〜21:00・定員3）
await setDay("normal");
s8 = await anonSlots(d8);
assert.equal(s8[0].slot, "16:00"); assert.equal(s8.at(-1).slot, "20:45");
assert.equal(s8.find(x => x.slot === "17:15").remaining, 2, "調整中に入った予約は残る");
assert.equal((await admin(`select count(*)::int c from pickup_date_overrides where pickup_date = $1`, [d8]))[0].c, 0);
await svc(`select cancel_pickup_reservation($1, $2)`, [cid.F, o1]);
ok("日付ごとの調整：その日だけの時間帯・定員・送迎なし・通常に戻す");

// ---- juku-desk への通知（L-4 / R2） ----
const SECRET = randomBytes(16).toString("hex");
const calls = async () => (await db.query(`select url, body, headers from net.calls order by id`)).rows;
await db.exec(`delete from net.calls`);
// 宛先が未設定のあいだは、承認しても何も送らない
const hook = await submit("H", n1, "17:00");
await admin(`select admin_approve_reservation($1)`, [hook]);
assert.equal((await calls()).length, 0, "宛先未設定では送らない");
await fails(db.query(`insert into rails_webhook (id, url, secret) values (1, 'http://x', 'short')`), /check/, "http と短い秘密は拒否");
await fails(as("authenticated", ADMIN, `select * from rails_webhook`), /permission denied/, "管理者のブラウザからも宛先・秘密は読めない");
await db.query(`insert into rails_webhook (id, url, secret) values (1, 'https://juku.example/internal/schedule_events', $1)`, [SECRET]);

// LIFF から入った予約（pending）を管理者が承認 → 通知が1件
const liff = await submit("G", n1, "18:00");
assert.equal((await admin(`select status from pickup_reservations where id = $1`, [liff]))[0].status, "pending");
await admin(`select admin_approve_reservation($1)`, [liff]);
let sent = await calls();
assert.equal(sent.length, 1);
assert.equal(sent[0].url, "https://juku.example/internal/schedule_events");
assert.deepEqual({ ...sent[0].body, student_id: undefined }, { event: "reservation_approved", reservation_id: liff, actor_id: ADMIN, pickup_date: n1, party_size: 1, student_id: undefined });
const h = sent[0].headers;
const expected = createHmac("sha256", SECRET).update(`${h["X-Schedule-Timestamp"]}.reservation_approved.${liff}.${ADMIN}`).digest("hex");
assert.equal(h["X-Schedule-Signature"], "sha256=" + expected, "Rails の ScheduleEventSignature と同じ署名");

// 却下は理由つき。承認済みの取り消しや、期限切れの自動却下（auth.uid なし）は送らない
const rej = await submit("F", n1, "19:00");
await admin(`select admin_reject_reservation($1, '定員超過')`, [rej]);
sent = await calls();
assert.equal(sent.length, 2);
assert.equal(sent[1].body.event, "reservation_rejected");
assert.equal(sent[1].body.reject_reason, "定員超過");
await svc(`select cancel_pickup_reservation($1, $2)`, [cid.G, liff]);
const expiring = await submit("E", n1, "19:30");
await db.exec(`reset role; update pickup_reservations set status = 'rejected', reject_reason = '期限切れ' where id = '${expiring}'`);
assert.equal((await calls()).length, 2, "取り消し・自動却下では送らない");
// 送信に失敗しても承認は成功する
await db.exec(`reset role; create or replace function net.http_post(url text, body jsonb default '{}', headers jsonb default '{}', timeout_milliseconds int default 5000) returns bigint language plpgsql as $$ begin raise exception 'net down'; end $$;`);
const down = await submit("D", n2, "17:00");
await admin(`select admin_approve_reservation($1)`, [down]);
assert.equal((await admin(`select status from pickup_reservations where id = $1`, [down]))[0].status, "approved");
ok("juku-desk への通知：承認・却下で1件ずつ、署名つき。未設定・自動却下・送信失敗では承認を邪魔しない");

// ---- 変更履歴 ----
const logs = (await admin(`select table_name, count(*)::int c from audit_log group by 1 order by 1`));
assert.ok(logs.some(l => l.table_name === "pickup_reservations") && logs.some(l => l.table_name === "students"));
ok("変更履歴に送迎・生徒の変更が残る");

console.log(`\n${passed} 項目すべて成功`);
