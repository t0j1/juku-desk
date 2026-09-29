#!/usr/bin/env node
// Supabase の events / event_types を anon キーで読み出し、CSV と JSON で保存する。
// 使い方: node scripts/backup.mjs --out <保存先フォルダ> [--keep 12]
// 環境変数: SUPABASE_URL, SUPABASE_ANON_KEY（service_role は使わない）
//
// 安全策: 取得・検証がすべて成功するまで、ファイルは1つも書かない／消さない。
//         API エラーや 0 件のときは exit 1 で終了する（空のバックアップで正常なデータを消さない）。

import { mkdir, readdir, rm, writeFile } from "node:fs/promises";
import { join } from "node:path";

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

async function fetchAll(base, key, table, select, order) {
  const rows = [];
  for (let from = 0; ; from += PAGE) {
    const res = await fetch(`${base}/rest/v1/${table}?select=${select}&order=${order}`, {
      headers: { apikey: key, Authorization: `Bearer ${key}`, "Range-Unit": "items", Range: `${from}-${from + PAGE - 1}` },
      signal: AbortSignal.timeout(30_000),
    });
    if (!res.ok) fail(`${table} の取得に失敗しました（HTTP ${res.status}）: ${(await res.text()).slice(0, 200)}`);
    const data = await res.json();
    if (!Array.isArray(data)) fail(`${table} の応答が配列ではありません。`);
    rows.push(...data);
    if (data.length < PAGE) return rows;
  }
}

const q = v => `"${String(v ?? "").replace(/"/g, '""')}"`;
const toCSV = rows => "﻿" + rows.map(r => r.map(q).join(",")).join("\r\n") + "\r\n";
const hhmm = t => (t ? String(t).slice(0, 5) : "");
const jstDate = () => new Date(Date.now() + 9 * 3600e3).toISOString().slice(0, 10);

async function main() {
  const { out, keep } = parseArgs(process.argv.slice(2));
  const key = process.env.SUPABASE_ANON_KEY;
  let base = (process.env.SUPABASE_URL || "").trim().replace(/\/+$/, "");
  if (!base || !key) fail("SUPABASE_URL と SUPABASE_ANON_KEY を設定してください。");
  if (/\/rest\/v1$/.test(base)) fail("SUPABASE_URL は Project URL のみ（末尾に /rest/v1 を付けない）にしてください。");

  // 1. 取得と検証（ここまでは何も書かない）
  const events = await fetchAll(base, key, "events",
    "id,event_date,type,title,start_time,end_time,note,is_published",
    "event_date.asc,start_time.asc.nullsfirst,id.asc");
  const types = await fetchAll(base, key, "event_types", "name,color,sort_order", "sort_order.asc,name.asc");
  if (events.length === 0) fail("events が 0 件でした。空のバックアップは保存しません。");
  if (types.length === 0) fail("event_types が 0 件でした。空のバックアップは保存しません。");

  // 2. 保存
  const date = jstDate();
  const stem = join(out, `backup-${date}`);
  await mkdir(out, { recursive: true });
  await writeFile(`${stem}.csv`, toCSV([
    ["日付", "種別", "内容", "開始時刻", "終了時刻", "備考", "公開"],
    ...events.map(e => [e.event_date, e.type, e.title, hhmm(e.start_time), hhmm(e.end_time), e.note, e.is_published ? "公開" : "下書き"]),
  ]));
  await writeFile(`${stem}.event_types.csv`, toCSV([
    ["種別", "色", "並び順"], ...types.map(t => [t.name, t.color, t.sort_order]),
  ]));
  await writeFile(`${stem}.json`, JSON.stringify({
    taken_at: new Date().toISOString(),
    note: "anon キーで読める公開分のみ（下書きは含まれません）",
    counts: { events: events.length, event_types: types.length },
    event_types: types,
    events,
  }, null, 2) + "\n");
  console.log(`backup-${date}: events=${events.length}, event_types=${types.length}`);

  // 3. 古いバックアップを削除（日付単位で直近 keep 回分を残す）
  const dates = [...new Set((await readdir(out)).map(f => f.match(/^backup-(\d{4}-\d{2}-\d{2})\./)?.[1]).filter(Boolean))].sort().reverse();
  for (const d of dates.slice(keep)) {
    for (const f of await readdir(out)) if (f.startsWith(`backup-${d}.`)) await rm(join(out, f));
    console.log(`removed old backup: ${d}`);
  }
}

main().catch(e => fail(`予期しないエラー: ${e.message}`));
