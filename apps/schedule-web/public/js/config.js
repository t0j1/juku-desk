// Supabase の接続情報。
// ここに置いてよいのは「Project URL」と「anon（公開）キー」だけです。
// service_role キーは絶対に書かないでください。
//
// 手元（localhost / 127.0.0.1）で開いたときは開発用プロジェクト、それ以外（公開サイト）は本番につながります。
// 手元から本番を確認したいときは、URL に ?db=prod を付けて開きます。
const SUPABASE_ENVS = {
  prod: { url: "https://qhdbpccbkhggyaussnkp.supabase.co", key: "sb_publishable_tNcGoyraTo8PHgNnIRyFEA_LFvUy_3X" },
  dev:  { url: "https://nwiahmtvxhqbllmrnhwt.supabase.co", key: "sb_publishable_IS979EX0336ZMRIv4srCNg_2PbDxh2i" },
};
const SUPABASE_ENV = ["localhost", "127.0.0.1"].includes(location.hostname) && new URLSearchParams(location.search).get("db") !== "prod"
  ? "dev" : "prod";
const SUPABASE_URL = SUPABASE_ENVS[SUPABASE_ENV].url;
const SUPABASE_ANON_KEY = SUPABASE_ENVS[SUPABASE_ENV].key;
