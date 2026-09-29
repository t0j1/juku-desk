// Edge Function pickup-api の本体（handler.ts）のテスト。DB と LINE は偽物に差し替える。
// 実行: node --test scripts/pickup-api.test.mjs （Node 23.6 以降。TypeScript をそのまま読み込む）
import test from "node:test";
import assert from "node:assert/strict";
import { makeHandler } from "../supabase/functions/pickup-api/handler.ts";

const ORIGIN = "http://localhost:8000";
const CONTACT = { contact_id: "c1", student_id: "s1", student_name: "田中", grade: "高2" };

function setup({ appEnv = "dev", rpcImpl = {}, line = null } = {}) {
  const calls = [];
  const logs = [];
  const handle = makeHandler({
    appEnv,
    allowedOrigins: [ORIGIN],
    log: (...a) => logs.push(a),
    verifyLineIdToken: async t => (t === "good" ? line ?? { sub: "U1", name: "たなか" } : null),
    rpc: async (fn, args) => {
      calls.push({ fn, args });
      if (rpcImpl[fn]) return rpcImpl[fn](args);
      if (fn === "find_contact") return { data: [CONTACT], error: null };
      return { data: null, error: null };
    },
  });
  const post = async (body, { origin = ORIGIN, raw } = {}) => {
    const res = await handle(new Request("http://x/pickup-api", {
      method: "POST", headers: { "Content-Type": "application/json", ...(origin ? { Origin: origin } : {}) },
      body: raw ?? JSON.stringify(body),
    }));
    return { status: res.status, body: await res.json(), headers: res.headers };
  };
  return { post, calls, logs, handle };
}

test("CORS: 許可したオリジンだけに Allow-Origin を返し、ほかは 403", async () => {
  const { post, handle } = setup();
  const ok = await post({ action: "me", email: "a@example.com" });
  assert.equal(ok.headers.get("Access-Control-Allow-Origin"), ORIGIN);
  const ng = await post({ action: "me", email: "a@example.com" }, { origin: "https://evil.example" });
  assert.equal(ng.status, 403);
  assert.equal(ng.headers.get("Access-Control-Allow-Origin"), null);
  const pre = await handle(new Request("http://x", { method: "OPTIONS", headers: { Origin: ORIGIN } }));
  assert.equal(pre.status, 204);
});

test("不正なリクエスト: JSON でない・不明な操作・POST 以外", async () => {
  const { post, handle } = setup();
  assert.equal((await post(null, { raw: "{" })).status, 400);
  assert.equal((await post(null, { raw: "[1]" })).status, 400);
  assert.equal((await post({ action: "drop_table" })).status, 400);
  assert.equal((await handle(new Request("http://x", { method: "GET" }))).status, 405);
});

test("本番ではメールアドレスでの本人確認はできない", async () => {
  const { post, calls } = setup({ appEnv: "prod" });
  const r = await post({ action: "submit", email: "a@example.com", date: "2026-10-01", time: "17:00" });
  assert.equal(r.status, 401);
  assert.match(r.body.error, /LINE/);
  assert.equal(calls.length, 0, "DB は呼ばれない");
});

test("LINE: ID トークンが正しければ LINE のユーザーIDで探す／不正なら 401", async () => {
  const { post, calls } = setup({ appEnv: "prod" });
  const ok = await post({ action: "me", id_token: "good" });
  assert.deepEqual(ok.body, { linked: true, student_name: "田中", grade: "高2" });
  assert.deepEqual(calls[0], { fn: "find_contact", args: { p_line_user_id: "U1", p_email: null } });
  const ng = await post({ action: "me", id_token: "forged" });
  assert.equal(ng.status, 401);
});

test("開発: メールアドレスは小文字にそろえ、形式が違えば 400", async () => {
  const { post, calls } = setup();
  await post({ action: "me", email: " A@Example.COM " });
  assert.equal(calls[0].args.p_email, "a@example.com");
  assert.equal((await post({ action: "me", email: "abc" })).status, 400);
});

test("未登録なら linked: false、予約しようとすると 403", async () => {
  const { post } = setup({ rpcImpl: { find_contact: () => ({ data: [], error: null }) } });
  assert.deepEqual((await post({ action: "me", email: "a@example.com" })).body, { linked: false });
  const r = await post({ action: "submit", email: "a@example.com", date: "2026-10-01", time: "17:00" });
  assert.equal(r.status, 403);
  assert.match(r.body.error, /登録コード/);
});

test("登録: コードと連絡先を DB 関数に渡す", async () => {
  const { post, calls } = setup({ rpcImpl: { link_student: () => ({ data: [{ student_name: "田中" }], error: null }) } });
  const r = await post({ action: "link", email: "a@example.com", code: "ABCD-EFGH" });
  assert.deepEqual(r.body, { linked: true, student_name: "田中" });
  assert.deepEqual(calls[0].args, { p_code: "ABCD-EFGH", p_line_user_id: null, p_email: "a@example.com", p_display_name: "a@example.com" });
  assert.equal((await post({ action: "link", email: "a@example.com", code: "" })).status, 400);
});

test("予約: 入力の形式を確かめてから、生徒の連絡先IDで DB 関数を呼ぶ", async () => {
  const { post, calls } = setup({ rpcImpl: { submit_pickup_reservation: () => ({ data: "r1", error: null }) } });
  const r = await post({ action: "submit", email: "a@example.com", date: "2026-10-01", time: "17:00", notes: "x".repeat(500) });
  assert.deepEqual(r.body, { id: "r1" });
  const sub = calls.find(c => c.fn === "submit_pickup_reservation");
  assert.equal(sub.args.p_contact_id, "c1");
  assert.equal(sub.args.p_notes.length, 300, "備考は300文字まで");
  for (const bad of [{ date: "10/1", time: "17:00" }, { date: "2026-10-01", time: "5pm" }]) {
    assert.equal((await post({ action: "submit", email: "a@example.com", ...bad })).status, 400);
  }
});

test("予約: 人数は1〜8の整数だけ。省略なら1名", async () => {
  const { post, calls } = setup({ rpcImpl: { submit_pickup_reservation: () => ({ data: "r1", error: null }) } });
  const base = { action: "submit", email: "a@example.com", date: "2026-10-01", time: "17:00" };
  await post(base);
  assert.equal(calls.at(-1).args.p_party_size, 1);
  await post({ ...base, party_size: 3 });
  assert.equal(calls.at(-1).args.p_party_size, 3);
  await post({ ...base, party_size: "2" });
  assert.equal(calls.at(-1).args.p_party_size, 2);
  for (const bad of [0, 9, 1.5, "abc", -1]) assert.equal((await post({ ...base, party_size: bad })).status, 400, `人数 ${bad}`);
});

test("DB の利用者向けエラー（PT400）はそのまま、それ以外は伏せて 500", async () => {
  const user = setup({ rpcImpl: { submit_pickup_reservation: () => ({ data: null, error: { code: "PT400", message: "その時刻は満席になりました。" } }) } });
  const a = await user.post({ action: "submit", email: "a@example.com", date: "2026-10-01", time: "17:00" });
  assert.equal(a.status, 400);
  assert.equal(a.body.error, "その時刻は満席になりました。");

  const internal = setup({ rpcImpl: { submit_pickup_reservation: () => ({ data: null, error: { code: "42P01", message: "relation secret_table does not exist" } }) } });
  const b = await internal.post({ action: "submit", email: "a@example.com", date: "2026-10-01", time: "17:00" });
  assert.equal(b.status, 500);
  assert.doesNotMatch(b.body.error, /secret_table/, "内部のエラー内容は利用者に見せない");
  assert.equal(internal.logs.length, 1, "サーバーのログには残す");
});

test("取り消し・回答: ID の形式を確かめる", async () => {
  const { post, calls } = setup();
  assert.equal((await post({ action: "cancel", email: "a@example.com", id: "1; drop" })).status, 400);
  const id = "0b7c3f7e-1d2a-4c5b-9e8f-0123456789ab";
  assert.equal((await post({ action: "cancel", email: "a@example.com", id })).status, 200);
  assert.deepEqual(calls.at(-1), { fn: "cancel_pickup_reservation", args: { p_contact_id: "c1", p_reservation_id: id } });
  await post({ action: "respond", email: "a@example.com", proposal_id: id, accept: "true" });
  assert.equal(calls.at(-1).args.p_accept, false, "accept は true（真偽値）のときだけ承認");
});

test("回答リンク: トークンは64桁の16進数だけ", async () => {
  const { post } = setup({ rpcImpl: { get_pickup_proposal_by_token: () => ({ data: [], error: null }) } });
  assert.equal((await post({ action: "proposal", token: "abc" })).status, 400);
  assert.equal((await post({ action: "proposal", token: "a".repeat(64) })).status, 404);
});
