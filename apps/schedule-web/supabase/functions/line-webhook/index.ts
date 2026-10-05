// Edge Function: line-webhook（LINE のボタン（postback）での回答）
// デプロイ: npx supabase functions deploy line-webhook --no-verify-jwt --project-ref <プロジェクトID>
//           （LINE から呼ばれるので Supabase の JWT 検証は使わない。代わりに X-Line-Signature で確認する）
// Secret:   LINE_CHANNEL_SECRET（Messaging API のチャネルシークレット）、LINE_CHANNEL_ACCESS_TOKEN（返信用）
//           SUPABASE_URL と SUPABASE_SERVICE_ROLE_KEY は Supabase が自動で渡す
// LINE Developers の Webhook URL: https://<プロジェクトID>.supabase.co/functions/v1/line-webhook
import { createClient } from "npm:@supabase/supabase-js@2";
import { makeHandler } from "./handler.ts";

const env = (k: string) => Deno.env.get(k) ?? "";
const db = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), { auth: { persistSession: false } });

async function reply(replyToken: string, text: string) {
  const res = await fetch("https://api.line.me/v2/bot/message/reply", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${env("LINE_CHANNEL_ACCESS_TOKEN")}` },
    body: JSON.stringify({ replyToken, messages: [{ type: "text", text }] }),
  });
  if (!res.ok) throw new Error(`LINE reply ${res.status}`);
}

Deno.serve(makeHandler({
  rpc: (fn, args) => db.rpc(fn, args) as never,
  channelSecret: env("LINE_CHANNEL_SECRET"),
  reply,
}));
