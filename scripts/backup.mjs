#!/usr/bin/env node
// Supabase の events / event_types を anon キーで読み出し、CSV と JSON で保存する。
// 使い方: node scripts/backup.mjs --out <保存先フォルダ> [--keep 12]
// 環境変数: SUPABASE_URL, SUPABASE_ANON_KEY（service_role は使わない）
//
// 安全策:
//  - まず一時フォルダに書き出し、読み直して検証する（件数・CSV往復・形式・急減チェック）。
//  - 検証を通ったときだけ --out に移す。失敗時は --out に一切触れない（既存のバックアップは無傷）。
//  - 検証の中身は scripts/backup-lib.mjs、テストは scripts/backup.test.mjs。

import { copyFile, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { buildFiles, loadCommon, verifyBackup } from "./backup-lib.mjs";

const PAGE = 1000;

function fail(msg) {
  console.error(`::error::${msg}`);
  process.exit(1);
}

function parseArgs(argv) {
  const a = { keep: 12 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--out") a.out = argv[++i];
    else if (argv[i] === "--keep") a.keep = Number(argv[++i]);
  }
  if (!a.out) fail("--out（保存先フォルダ）を指定してください。");
  if (!Number.isInteger(a.keep) || a.keep < 1) fail("--keep は1以上の整数にしてください。");
  return a;
}

const api = (base, key, path, extra = {}) =>
  fetch(`${base}/rest/v1/${path}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}`, "Range-Unit": "items", ...extra },
    signal: AbortSignal.timeout(30_000),
  });

async function fetchAll(base, key, table, select, order) {
  const rows = [];
  for (let from = 0; ; from += PAGE) {
    const res = await api(base, key, `${table}?select=${select}&order=${order}`, { Range: `${from}-${from + PAGE - 1}` });
    if (!res.ok) fail(`${table} の取得に失敗しました（HTTP ${res.status}）: ${(await res.text()).slice(0, 200)}`);
    const data = await res.json();
    if (!Array.isArray(data)) fail(`${table} の応答が配列ではありません。`);
    rows.push(...data);
    if (data.length < PAGE) return rows;
  }
}

// DB 側の総件数（別クエリ）。取得件数との突き合わせ用
async function countRows(base, key, table) {
  const res = await api(base, key, `${table}?select=*`, { Range: "0-0", Prefer: "count=exact" });
  if (!res.ok) fail(`${table} の件数取得に失敗しました（HTTP ${res.status}）`);
  const m = (res.headers.get("content-range") || "").match(/\/(\d+)$/);
  if (!m) fail(`${table} の総件数を取得できませんでした（Content-Range なし）。`);
  return Number(m[1]);
}

const jstDate = () => new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);
const datesIn = names => [...new Set(names.map(f => f.match(/^backup-(\d{4}-\d{2}-\d{2})\./)?.[1]).filter(Boolean))].sort();

// 直前のバックアップ（今日の日付以外で最新のもの）の件数
async function previousCounts(out, today) {
  let names;
  try { names = await readdir(out); } catch { return null; }
  const prevDate = datesIn(names).filter(d => d < today).pop();
  if (!prevDate) return null;
  try {
    const c = JSON.parse(await readFile(join(out, `backup-${prevDate}.json`), "utf8")).counts;
    if (!Number.isInteger(c?.events) || !Number.isInteger(c?.event_types)) throw new Error("counts なし");
    return { events: c.events, event_types: c.event_types };
  } catch (e) {
    console.log(`::warning::直前のバックアップ（${prevDate}）の件数を読めないため、急減チェックを省略します: ${e.message}`);
    return null;
  }
}

async function main() {
  const { out, keep } = parseArgs(process.argv.slice(2));
  const key = process.env.SUPABASE_ANON_KEY;
  const base = (process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
  if (!base || !key) fail("SUPABASE_URL と SUPABASE_ANON_KEY を設定してください。");
  if (/\/rest\/v1$/.test(base)) fail("SUPABASE_URL は Project URL のみ（末尾に /rest/v1 を付けない）にしてください。");

  // 1. 取得
  const events = await fetchAll(base, key, "events",
    "id,event_date,type,title,start_time,end_time,note,is_published",
    "event_date.asc,start_time.asc.nullsfirst,id.asc");
  const types = await fetchAll(base, key, "event_types", "name,color,sort_order", "sort_order.asc,name.asc");
  const dbCounts = { events: await countRows(base, key, "events"), event_types: await countRows(base, key, "event_types") };

  // 2. 一時フォルダに書き出し → 読み直して検証（--out には触れない）
  const date = jstDate(), stem = `backup-${date}`;
  const files = buildFiles(events, types, new Date().toISOString());
  const stage = await mkdtemp(join(tmpdir(), "sekigaku-backup-"));
  try {
    await writeFile(join(stage, `${stem}.csv`), files.csv);
    await writeFile(join(stage, `${stem}.event_types.csv`), files.typesCsv);
    await writeFile(join(stage, `${stem}.json`), files.json);
    const read = n => readFile(join(stage, n), "utf8");
    const errors = verifyBackup({
      events, types, dbCounts,
      csv: await read(`${stem}.csv`), typesCsv: await read(`${stem}.event_types.csv`), json: await read(`${stem}.json`),
      prev: await previousCounts(out, date),
      common: loadCommon(),
    });
    if (errors.length) {
      errors.forEach(e => console.error(`::error::検証エラー ${e}`));
      console.error(`::error::検証に失敗しました（${errors.length} 件）。既存のバックアップは変更していません。`);
      await rm(stage, { recursive: true, force: true });
      process.exit(1);
    }

    // 3. 検証を通ったので、本番の保存先へ移す
    await mkdir(out, { recursive: true });
    for (const n of [`${stem}.csv`, `${stem}.event_types.csv`, `${stem}.json`]) await copyFile(join(stage, n), join(out, n));
    console.log(`${stem}: events=${events.length}, event_types=${types.length}（検証OK）`);

    // 4. 古いバックアップを削除（日付単位で直近 keep 回分を残す）
    const names = await readdir(out);
    for (const d of datesIn(names).reverse().slice(keep)) {
      for (const f of names) if (f.startsWith(`backup-${d}.`)) await rm(join(out, f));
      console.log(`removed old backup: ${d}`);
    }
  } finally {
    await rm(stage, { recursive: true, force: true });
  }
}

main().catch(e => fail(`予期しないエラー: ${e.message}`));
