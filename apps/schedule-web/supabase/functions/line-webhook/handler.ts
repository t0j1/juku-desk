// LINE の Webhook の本体（Deno にも Supabase にも LINE の API にも依存しない。テストは scripts/line-webhook.test.mjs）。
// 1. X-Line-Signature（本文の HMAC-SHA256 を base64 にしたもの）を確認する。合わなければ 401
// 2. postback（相乗り打診の承諾・辞退）を、押した人の LINE ユーザーIDから生徒を探して DB 関数に渡す
// 3. 結果（確定した／回答済み／期限切れ／本人ではない など）を LINE で返信する
// 同じイベント（webhookEventId）が2回届いても、1回だけ処理する。LINE は 2xx 以外だと再送するので、処理した結果は 200 で返す
//
// postback.data の形式: "a=pickup&id=<打診のID>&r=accept" / "...&r=decline"（相乗り打診のボタンに入れる）

export type RpcResult = { data: unknown; error: { code?: string; message: string } | null };
export type Rpc = (fn: string, args: Record<string, unknown>) => Promise<RpcResult>;

export type Deps = {
  rpc: Rpc;
  channelSecret: string;
  reply: (replyToken: string, text: string) => Promise<void>;   // LINE Messaging API の reply
  log?: (...a: unknown[]) => void;
};

type LineEvent = {
  type?: string;
  webhookEventId?: string;
  replyToken?: string;
  source?: { type?: string; userId?: string };
  postback?: { data?: string };
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_BODY = 1_000_000;

const enc = new TextEncoder();

export async function signatureOf(secret: string, body: string): Promise<string> {
  const key = await crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, enc.encode(body)));
  let bin = "";
  for (const b of mac) bin += String.fromCharCode(b);
  return btoa(bin);
}

// 長さが違っても、先頭が合っていても、同じ時間で比べる
function safeEqual(a: string, b: string): boolean {
  const x = enc.encode(a), y = enc.encode(b);
  let diff = x.length ^ y.length;
  for (let i = 0; i < Math.max(x.length, y.length); i++) diff |= (x[i] ?? 0) ^ (y[i] ?? 0);
  return diff === 0;
}

export function parsePostback(data: string | undefined): { proposalId: string; accept: boolean } | null {
  if (!data) return null;
  const p = new URLSearchParams(data);
  const id = p.get("id") ?? "";
  const r = p.get("r");
  if (p.get("a") !== "pickup" || !UUID_RE.test(id) || (r !== "accept" && r !== "decline")) return null;
  return { proposalId: id, accept: r === "accept" };
}

export function makeHandler(deps: Deps) {
  const log = deps.log ?? console.error;

  // 返信は失敗しても処理は済んでいるので、記録だけして先へ進む
  async function say(token: string | undefined, text: string) {
    if (!token) return;
    try { await deps.reply(token, text); } catch (e) { log("reply failed", e); }
  }

  async function onPostback(ev: LineEvent) {
    const pb = parsePostback(ev.postback?.data);
    if (!pb) return say(ev.replyToken, "この操作は受け付けられませんでした。");
    const userId = ev.source?.type === "user" ? ev.source.userId : undefined;
    if (!userId) return say(ev.replyToken, "この操作は、ご本人との個別のトークからお願いします。");

    const found = await deps.rpc("find_contact", { p_line_user_id: userId, p_email: null });
    if (found.error) throw new Error(`find_contact: ${found.error.message}`);
    const contact = (found.data as { contact_id: string }[] | null)?.[0];
    if (!contact) return say(ev.replyToken, "生徒の登録が確認できません。登録コードを入力してから、もう一度お試しください。");

    const res = await deps.rpc("respond_pickup_proposal", {
      p_contact_id: contact.contact_id, p_proposal_id: pb.proposalId, p_accept: pb.accept,
    });
    if (res.error) {
      // 回答できない理由（回答済み・期限切れ・本人の予約ではない）は、DB 関数が日本語で返す
      if (res.error.code === "PT400") return say(ev.replyToken, res.error.message);
      throw new Error(`respond_pickup_proposal: ${res.error.message}`);
    }
    if (!pb.accept) return say(ev.replyToken, "辞退しました。ご連絡ありがとうございます。");
    return say(ev.replyToken, res.data === "confirmed"
      ? "承諾しました。全員の承諾がそろったので、送迎が確定しました。"
      : "承諾しました。ほかの方の回答がそろうまでお待ちください。");
  }

  return async function handle(req: Request): Promise<Response> {
    if (req.method !== "POST") return new Response("POST only", { status: 405 });
    if (!deps.channelSecret) { log("LINE_CHANNEL_SECRET is not set"); return new Response("unauthorized", { status: 401 }); }

    const body = await req.text();
    if (body.length > MAX_BODY) return new Response("too large", { status: 413 });
    const sig = req.headers.get("X-Line-Signature") ?? "";
    if (!sig || !safeEqual(sig, await signatureOf(deps.channelSecret, body))) return new Response("invalid signature", { status: 401 });

    let events: LineEvent[];
    try {
      const parsed = JSON.parse(body);
      events = Array.isArray(parsed?.events) ? parsed.events : [];
    } catch {
      return new Response("bad request", { status: 400 });
    }

    for (const ev of events) {
      try {
        if (ev?.type !== "postback") continue;      // 友だち追加などは、いまは何もしない
        if (ev.webhookEventId) {
          const claim = await deps.rpc("pickup_claim_line_event", { p_event_id: ev.webhookEventId });
          if (claim.error) throw new Error(`pickup_claim_line_event: ${claim.error.message}`);
          if (claim.data !== true) continue;        // 同じイベントは処理済み
        }
        await onPostback(ev);
      } catch (e) {
        log("event failed", e);
        await say(ev?.replyToken, "サーバーでエラーが起きました。時間をおいて、もう一度お試しください。");
      }
    }
    return new Response("ok", { status: 200 });
  };
}
