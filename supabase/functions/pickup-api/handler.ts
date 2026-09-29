// 送迎予約の利用者向け API の本体（Deno にも Supabase にも依存しない。テストは scripts/pickup-api.test.mjs）。
// 本人確認（本番: LINE の ID トークン / 開発: メールアドレス）をしてから、service_role で DB 関数を呼ぶ。
// DB 関数が SQLSTATE PT400 で返したエラーだけを、利用者向けの文としてそのまま返す。

export type RpcResult = { data: unknown; error: { code?: string; message: string } | null };
export type Rpc = (fn: string, args: Record<string, unknown>) => Promise<RpcResult>;
export type LineProfile = { sub: string; name?: string };

export type Deps = {
  rpc: Rpc;
  verifyLineIdToken: (idToken: string) => Promise<LineProfile | null>;
  appEnv: string;                 // "dev" | "prod"
  allowedOrigins: string[];
  log?: (...a: unknown[]) => void;
};

type Identity = { line_user_id: string | null; email: string | null; display_name: string };
type Contact = { contact_id: string; student_id: string; student_name: string; grade: string };

class UserError extends Error {
  status: number;
  constructor(message: string, status = 400) { super(message); this.status = status; }
}

const EMAIL_RE = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const TIME_RE = /^\d{2}:\d{2}$/;

const str = (v: unknown, max = 200) => (typeof v === "string" ? v.trim().slice(0, max) : "");
function need(v: unknown, re: RegExp, label: string): string {
  const s = str(v);
  if (!re.test(s)) throw new UserError(`${label}が正しくありません。`);
  return s;
}

export function makeHandler(deps: Deps) {
  const log = deps.log ?? console.error;
  const isDev = deps.appEnv === "dev";

  async function call<T>(fn: string, args: Record<string, unknown>): Promise<T> {
    const { data, error } = await deps.rpc(fn, args);
    if (error) {
      if (error.code === "PT400") throw new UserError(error.message);
      log(`rpc ${fn} failed`, error);
      throw new UserError("サーバーでエラーが起きました。時間をおいて、もう一度お試しください。", 500);
    }
    return data as T;
  }

  async function identify(body: Record<string, unknown>): Promise<Identity> {
    const idToken = str(body.id_token, 4096);
    if (idToken) {
      const p = await deps.verifyLineIdToken(idToken);
      if (!p?.sub) throw new UserError("LINE の確認に失敗しました。LINE のメニューから開き直してください。", 401);
      return { line_user_id: p.sub, email: null, display_name: str(p.name, 100) };
    }
    if (isDev && body.email !== undefined) {
      const email = str(body.email).toLowerCase();
      if (!EMAIL_RE.test(email)) throw new UserError("メールアドレスが正しくありません。");
      return { line_user_id: null, email, display_name: email };
    }
    throw new UserError(isDev ? "メールアドレスを入力してください。" : "LINE のメニューから開いてください。", 401);
  }

  async function findContact(id: Identity): Promise<Contact | null> {
    const rows = await call<Contact[]>("find_contact", { p_line_user_id: id.line_user_id, p_email: id.email });
    return rows?.[0] ?? null;
  }
  async function requireContact(id: Identity): Promise<Contact> {
    const c = await findContact(id);
    if (!c) throw new UserError("生徒の登録が確認できません。登録コードを入力してください。", 403);
    return c;
  }

  const actions: Record<string, (body: Record<string, unknown>) => Promise<unknown>> = {
    // 結び付いている生徒（無ければ linked: false）
    async me(body) {
      const c = await findContact(await identify(body));
      return c ? { linked: true, student_name: c.student_name, grade: c.grade } : { linked: false };
    },
    // 登録コードで結び付ける
    async link(body) {
      const id = await identify(body);
      const code = str(body.code, 40);
      if (!code) throw new UserError("登録コードを入力してください。");
      const rows = await call<{ student_name: string }[]>("link_student", {
        p_code: code, p_line_user_id: id.line_user_id, p_email: id.email, p_display_name: id.display_name,
      });
      return { linked: true, student_name: rows[0].student_name };
    },
    async submit(body) {
      const c = await requireContact(await identify(body));
      const id = await call<string>("submit_pickup_reservation", {
        p_contact_id: c.contact_id,
        p_date: need(body.date, DATE_RE, "日付"),
        p_time: need(body.time, TIME_RE, "時刻"),
        p_notes: str(body.notes, 300),
      });
      return { id };
    },
    async mine(body) {
      const c = await requireContact(await identify(body));
      return { reservations: await call<unknown[]>("my_pickup_reservations", { p_contact_id: c.contact_id }) };
    },
    async cancel(body) {
      const c = await requireContact(await identify(body));
      await call("cancel_pickup_reservation", { p_contact_id: c.contact_id, p_reservation_id: need(body.id, UUID_RE, "予約") });
      return { ok: true };
    },
    async respond(body) {
      const c = await requireContact(await identify(body));
      const status = await call<string>("respond_pickup_proposal", {
        p_contact_id: c.contact_id, p_proposal_id: need(body.proposal_id, UUID_RE, "打診"), p_accept: body.accept === true,
      });
      return { group_status: status };
    },
    // 開発用：メールのリンク（トークン）で打診を表示・回答する
    async proposal(body) {
      const rows = await call<unknown[]>("get_pickup_proposal_by_token", { p_token: need(body.token, /^[0-9a-f]{64}$/, "リンク") });
      if (!rows?.length) throw new UserError("このリンクは無効です。", 404);
      return { proposal: rows[0] };
    },
    async respond_token(body) {
      const status = await call<string>("respond_pickup_proposal_by_token", {
        p_token: need(body.token, /^[0-9a-f]{64}$/, "リンク"), p_accept: body.accept === true,
      });
      return { group_status: status };
    },
  };

  function corsHeaders(origin: string | null): Record<string, string> {
    const allowed = origin && deps.allowedOrigins.includes(origin) ? origin : "";
    return {
      ...(allowed ? { "Access-Control-Allow-Origin": allowed } : {}),
      "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Vary": "Origin",
    };
  }

  return async function handle(req: Request): Promise<Response> {
    const cors = corsHeaders(req.headers.get("Origin"));
    const json = (status: number, body: unknown) =>
      new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json; charset=utf-8" } });

    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
    if (req.method !== "POST") return json(405, { error: "POST だけ使えます。" });
    const origin = req.headers.get("Origin");
    if (origin && !deps.allowedOrigins.includes(origin)) return json(403, { error: "このページからは使えません。" });

    let body: Record<string, unknown>;
    try {
      const parsed = await req.json();
      if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("not an object");
      body = parsed as Record<string, unknown>;
    } catch {
      return json(400, { error: "リクエストの形式が正しくありません。" });
    }
    const action = actions[str(body.action, 40)];
    if (!action) return json(400, { error: "不明な操作です。" });

    try {
      return json(200, await action(body));
    } catch (e) {
      if (e instanceof UserError) return json(e.status, { error: e.message });
      log("unexpected", e);
      return json(500, { error: "サーバーでエラーが起きました。時間をおいて、もう一度お試しください。" });
    }
  };
}
