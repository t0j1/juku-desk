// Supabase 無料プランの自動停止（1週間アクセスなし）を防ぐための cron Worker。
// 3日おきに events を1件読むだけ。anon キーで動くので、書き込み権限は持たない。
export default {
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(ping(env));
  },
  // 動作確認用: デプロイ後に Worker の URL を開くと結果が見える
  async fetch(_request, env) {
    const r = await ping(env);
    return new Response(JSON.stringify(r), { headers: { "content-type": "application/json" } });
  },
};

async function ping(env) {
  const res = await fetch(`${env.SUPABASE_URL}/rest/v1/events?select=id&limit=1`, {
    headers: { apikey: env.SUPABASE_ANON_KEY, Authorization: `Bearer ${env.SUPABASE_ANON_KEY}` },
  });
  const ok = res.ok;
  console.log(`keepalive: ${res.status}`);
  if (!ok) throw new Error(`keepalive failed: HTTP ${res.status}`);
  return { ok, status: res.status };
}
