// Edge Function: pickup-api（送迎予約の利用者向け API）
// デプロイ: npx supabase functions deploy pickup-api --no-verify-jwt --project-ref <プロジェクトID>
// Secret:   APP_ENV（dev / prod）、ALLOWED_ORIGINS（カンマ区切り）、LINE_LOGIN_CHANNEL_ID（本番）
//           SUPABASE_URL と SUPABASE_SERVICE_ROLE_KEY は Supabase が自動で渡す
import { createClient } from "npm:@supabase/supabase-js@2";
import { makeHandler, type LineProfile } from "./handler.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });
const appEnv = env("APP_ENV") || "prod";
const lineChannelId = env("LINE_LOGIN_CHANNEL_ID");

// LINE ログインの ID トークンを、LINE のサーバーに問い合わせて確認する
async function verifyLineIdToken(idToken: string): Promise<LineProfile | null> {
  if (!lineChannelId) return null;
  const res = await fetch("https://api.line.me/oauth2/v2.1/verify", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ id_token: idToken, client_id: lineChannelId }),
  });
  if (!res.ok) return null;
  const p = await res.json();
  return typeof p.sub === "string" ? { sub: p.sub, name: p.name } : null;
}

const handle = makeHandler({
  rpc: (fn, args) => db.rpc(fn, args) as never,
  verifyLineIdToken,
  appEnv,
  allowedOrigins: env("ALLOWED_ORIGINS").split(",").map(s => s.trim()).filter(Boolean),
});

Deno.serve(handle);
