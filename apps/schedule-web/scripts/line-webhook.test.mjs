// Edge Function line-webhook の本体（handler.ts）のテスト。DB と LINE の API は偽物に差し替える。
// 実行: node --test scripts/line-webhook.test.mjs （Node 23.6 以降。TypeScript をそのまま読み込む）
import test from "node:test";
import assert from "node:assert/strict";
import { createHmac } from "node:crypto";
import { makeHandler, parsePostback, signatureOf } from "../supabase/functions/line-webhook/handler.ts";

const SECRET = "test-channel-secret";
const PID = "0f0f0f0f-1111-4222-8333-444444444444";
const CONTACT = { contact_id: "c1", student_id: "s1", student_name: "田中", grade: "高2" };

const postback = (over = {}, data = `a=pickup&id=${PID}&r=accept`) => ({
  type: "postback", webhookEventId: "ev1", replyToken: "rt1",
  source: { type: "user", userId: "U1" }, postback: { data }, ...over,
});
const sign = body => createHmac("sha256", SECRET).update(body).digest("base64");

function setup({ rpcImpl = {}, replyFails = false, secret = SECRET } = {}) {
  const calls = [], replies = [], logs = [];
  const seen = new Set();
  const handle = makeHandler({
    channelSecret: secret,
    log: (...a) => logs.push(a),
    reply: async (token, text) => { if (replyFails) throw new Error("LINE down"); replies.push({ token, text }); },
    rpc: async (fn, args) => {
      calls.push({ fn, args });
      if (rpcImpl[fn]) return rpcImpl[fn](args);
      if (fn === "pickup_claim_line_event") { const fresh = !seen.has(args.p_event_id); seen.add(args.p_event_id); return { data: fresh, error: null }; }
      if (fn === "find_contact") return { data: [CONTACT], error: null };
      if (fn === "respond_pickup_proposal") return { data: "proposing", error: null };
      return { data: null, error: null };
    },
  });
  const send = async (events, { signature, body: raw, method = "POST" } = {}) => {
    const body = raw ?? JSON.stringify({ destination: "Ubot", events });
    const headers = { "Content-Type": "application/json" };
    const sig = signature === undefined ? sign(body) : signature;
    if (sig !== null) headers["X-Line-Signature"] = sig;
    const res = await handle(new Request("http://x/line-webhook", { method, headers, body: method === "POST" ? body : undefined }));
    return { status: res.status, text: await res.text() };
  };
  const rpcs = fn => calls.filter(c => c.fn === fn);
  return { send, calls, replies, logs, rpcs, handle };
}

// ---- 署名 ----

test("署名の計算は LINE の仕様（本文の HMAC-SHA256 を base64）と一致する", async () => {
  assert.equal(await signatureOf(SECRET, "{}"), sign("{}"));
});

test("署名が無い・違う・本文が改ざんされている → 401 で、DB にも LINE にも触れない", async () => {
  const { send, calls, replies } = setup();
  assert.equal((await send([postback()], { signature: null })).status, 401);
  assert.equal((await send([postback()], { signature: "" })).status, 401);
  assert.equal((await send([postback()], { signature: sign("other") })).status, 401);
  const body = JSON.stringify({ events: [postback()] });
  assert.equal((await send([], { body, signature: sign(body.replace("accept", "decline")) })).status, 401);
  assert.equal(calls.length, 0);
  assert.equal(replies.length, 0);
});

test("別のチャネルシークレットで署名したものは 401、シークレット未設定なら何を送っても 401", async () => {
  const body = JSON.stringify({ events: [postback()] });
  const other = createHmac("sha256", "someone-else").update(body).digest("base64");
  assert.equal((await setup().send([], { body, signature: other })).status, 401);
  const unset = setup({ secret: "" });
  assert.equal((await unset.send([], { body, signature: sign(body) })).status, 401);
  assert.equal((await unset.send([], { body, signature: createHmac("sha256", "").update(body).digest("base64") })).status, 401);
  assert.equal(unset.calls.length, 0);
});

test("POST 以外は 405、署名が正しくても JSON でなければ 400", async () => {
  const { send } = setup();
  assert.equal((await send([], { method: "GET" })).status, 405);
  assert.equal((await send([], { body: "{" })).status, 400);
});

test("events が空（LINE の疎通確認）は 200", async () => {
  const { send, calls } = setup();
  assert.equal((await send([])).status, 200);
  assert.equal(calls.length, 0);
});

// ---- postback の読み取り ----

test("postback.data は a=pickup・UUID の id・r=accept|decline のときだけ受け付ける", () => {
  assert.deepEqual(parsePostback(`a=pickup&id=${PID}&r=accept`), { proposalId: PID, accept: true });
  assert.deepEqual(parsePostback(`a=pickup&id=${PID}&r=decline`), { proposalId: PID, accept: false });
  for (const bad of [undefined, "", "x", `a=other&id=${PID}&r=accept`, `a=pickup&id=1&r=accept`, `a=pickup&id=${PID}&r=maybe`, `a=pickup&r=accept`])
    assert.equal(parsePostback(bad), null, String(bad));
});

// ---- 承諾・辞退 ----

test("承諾: 押した人の LINE ユーザーIDから生徒を探し、その連絡先で回答して返信する", async () => {
  const { send, rpcs, replies } = setup();
  assert.equal((await send([postback()])).status, 200);
  assert.deepEqual(rpcs("find_contact")[0].args, { p_line_user_id: "U1", p_email: null });
  assert.deepEqual(rpcs("respond_pickup_proposal")[0].args, { p_contact_id: "c1", p_proposal_id: PID, p_accept: true });
  assert.deepEqual(replies, [{ token: "rt1", text: "承諾しました。ほかの方の回答がそろうまでお待ちください。" }]);
});

test("承諾して便が確定したら、確定したと返信する", async () => {
  const { send, replies } = setup({ rpcImpl: { respond_pickup_proposal: () => ({ data: "confirmed", error: null }) } });
  await send([postback()]);
  assert.match(replies[0].text, /送迎が確定しました/);
});

test("辞退", async () => {
  const { send, rpcs, replies } = setup();
  await send([postback({}, `a=pickup&id=${PID}&r=decline`)]);
  assert.equal(rpcs("respond_pickup_proposal")[0].args.p_accept, false);
  assert.match(replies[0].text, /辞退しました/);
});

// ---- 拒否 ----

test("回答済み・期限切れ・本人の予約ではない: DB 関数の文をそのまま返信し、200 を返す", async () => {
  for (const message of ["この打診には回答できません（期限切れ、または回答済みです）。", "この打診には回答できません。"]) {
    const { send, replies, logs } = setup({ rpcImpl: { respond_pickup_proposal: () => ({ data: null, error: { code: "PT400", message } }) } });
    assert.equal((await send([postback()])).status, 200);
    assert.deepEqual(replies, [{ token: "rt1", text: message }]);
    assert.equal(logs.length, 0, "利用者の操作の結果なのでエラーログは出さない");
  }
});

test("生徒に結び付いていない LINE アカウント: 回答せず、登録を案内する", async () => {
  const { send, rpcs, replies } = setup({ rpcImpl: { find_contact: () => ({ data: [], error: null }) } });
  await send([postback()]);
  assert.equal(rpcs("respond_pickup_proposal").length, 0);
  assert.match(replies[0].text, /登録コード/);
});

test("グループなど個別トークでない・ユーザーIDが無い・形式が違うボタン: 回答しない", async () => {
  const { send, rpcs, replies } = setup();
  await send([
    postback({ webhookEventId: "g", source: { type: "group", groupId: "G1", userId: "U1" } }),
    postback({ webhookEventId: "n", source: { type: "user" } }),
    postback({ webhookEventId: "b" }, "a=pickup&id=zzz&r=accept"),
  ]);
  assert.equal(rpcs("respond_pickup_proposal").length, 0);
  assert.equal(replies.length, 3);
});

test("postback 以外（友だち追加・メッセージ）は何もしない", async () => {
  const { send, calls, replies } = setup();
  assert.equal((await send([{ type: "follow", replyToken: "r", source: { type: "user", userId: "U1" } },
                            { type: "message", replyToken: "r2", message: { type: "text", text: "a" } }])).status, 200);
  assert.equal(calls.length, 0);
  assert.equal(replies.length, 0);
});

// ---- 二重処理 ----

test("同じイベントが2回届いても、回答も返信も1回だけ", async () => {
  const { send, rpcs, replies } = setup();
  const ev = postback();
  assert.equal((await send([ev])).status, 200);
  assert.equal((await send([ev])).status, 200);
  assert.equal(rpcs("respond_pickup_proposal").length, 1);
  assert.equal(replies.length, 1);
});

test("同じ本文の中に同じイベントが2つあっても1回だけ。別のイベントは別々に処理する", async () => {
  const { send, rpcs } = setup();
  await send([postback(), postback(), postback({ webhookEventId: "ev2" }, `a=pickup&id=${PID}&r=decline`)]);
  assert.equal(rpcs("respond_pickup_proposal").length, 2);
});

// ---- 失敗 ----

test("DB のエラー: 利用者にはエラーを返信し、詳細はログだけ。LINE には 200（再送で二重にならないように）", async () => {
  const { send, replies, logs } = setup({ rpcImpl: { respond_pickup_proposal: () => ({ data: null, error: { code: "XX000", message: "secret detail" } }) } });
  assert.equal((await send([postback()])).status, 200);
  assert.match(replies[0].text, /エラー/);
  assert.doesNotMatch(replies[0].text, /secret detail/);
  assert.ok(logs.length > 0);
});

test("LINE への返信が失敗しても、処理は済んでいるので 200", async () => {
  const { send, rpcs, logs } = setup({ replyFails: true });
  assert.equal((await send([postback()])).status, 200);
  assert.equal(rpcs("respond_pickup_proposal").length, 1);
  assert.ok(logs.length > 0);
});
