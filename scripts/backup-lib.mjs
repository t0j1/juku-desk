// バックアップの生成と検証（純粋関数）。backup.mjs とテストから使う。
import { readFileSync } from "node:fs";
import vm from "node:vm";
import { isDeepStrictEqual } from "node:util";

export const CSV_HEAD = ["日付", "種別", "内容", "開始時刻", "終了時刻", "備考", "公開"];
export const TYPES_CSV_HEAD = ["種別", "色", "並び順"];

const q = v => `"${String(v ?? "").replace(/"/g, '""')}"`;
export const toCSV = rows => "﻿" + rows.map(r => r.map(q).join(",")).join("\r\n") + "\r\n";
export const hhmm = t => (t ? String(t).slice(0, 5) : "");

// 管理画面と同じ CSV 解析関数（public/js/common.js）を、そのまま読み込む
export function loadCommon() {
  const src = readFileSync(new URL("../public/js/common.js", import.meta.url), "utf8");
  return vm.runInNewContext(`${src}\n;({ parseCSV, normDate, normTime })`, {});
}

export function buildFiles(events, types, takenAt) {
  return {
    csv: toCSV([CSV_HEAD, ...events.map(e => [e.event_date, e.type, e.title, hhmm(e.start_time), hhmm(e.end_time), e.note, e.is_published ? "公開" : "下書き"])]),
    typesCsv: toCSV([TYPES_CSV_HEAD, ...types.map(t => [t.name, t.color, t.sort_order])]),
    json: JSON.stringify({
      taken_at: takenAt,
      note: "anon キーで読める公開分のみ（下書きは含まれません）",
      counts: { events: events.length, event_types: types.length },
      event_types: types,
      events,
    }, null, 2) + "\n",
  };
}

const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$/;
const COLOR_RE = /^#[0-9a-fA-F]{6}$/;
const MAX_REPORT = 5;

/**
 * 検証。問題点のメッセージ配列を返す（空なら合格）。
 * @param events / types  DB から取得した元データ
 * @param dbCounts        DB へ別クエリで問い合わせた総件数 { events, event_types }
 * @param csv, typesCsv, json  ディスクに書き出したものを読み直した文字列
 * @param prev            直前のバックアップの件数 { events, event_types } または null
 * @param common          loadCommon() の結果
 */
export function verifyBackup({ events, types, dbCounts, csv, typesCsv, json, prev, common }) {
  const errs = [];
  const err = m => errs.push(m);
  const limited = (label, list) => list.slice(0, MAX_REPORT).forEach(m => err(`${label}: ${m}`)) ||
    (list.length > MAX_REPORT && err(`${label}: ほか ${list.length - MAX_REPORT} 件`));

  if (events.length === 0) err("events が 0 件です");
  if (types.length === 0) err("event_types が 0 件です");

  // ---- 1. 件数の一致 ----
  if (dbCounts.events !== events.length) err(`[件数] events: DB の総数 ${dbCounts.events} 件 ≠ 取得 ${events.length} 件`);
  if (dbCounts.event_types !== types.length) err(`[件数] event_types: DB の総数 ${dbCounts.event_types} 件 ≠ 取得 ${types.length} 件`);

  let j = null;
  try { j = JSON.parse(json); } catch { err("[JSON] JSON として読み込めません"); }
  if (j) {
    if (j.counts?.events !== events.length) err(`[件数] JSON counts.events = ${j.counts?.events} ≠ ${events.length}`);
    if (j.counts?.event_types !== types.length) err(`[件数] JSON counts.event_types = ${j.counts?.event_types} ≠ ${types.length}`);
    if (!Array.isArray(j.events) || j.events.length !== events.length) err(`[件数] JSON の events 配列 ${j.events?.length} 件 ≠ ${events.length} 件`);
    else if (!isDeepStrictEqual(j.events, events)) err("[内容] JSON の events が元データと一致しません");
    if (!Array.isArray(j.event_types) || j.event_types.length !== types.length) err(`[件数] JSON の event_types 配列 ${j.event_types?.length} 件 ≠ ${types.length} 件`);
    else if (!isDeepStrictEqual(j.event_types, types)) err("[内容] JSON の event_types が元データと一致しません");
  }

  // ---- 2. CSV を管理画面と同じ解析関数で読み直し、元データと比較 ----
  let rows = null;
  try { rows = common.parseCSV(csv); } catch (e) { err(`[CSV] 解析に失敗: ${e.message}`); }
  if (rows) {
    const head = rows[0] || [];
    if (head.length !== CSV_HEAD.length || CSV_HEAD.some((h, i) => head[i] !== h)) err(`[CSV] 見出し行が想定と違います: ${head.join(",")}`);
    const body = rows.slice(1);
    if (body.length !== events.length) err(`[件数] CSV の行数 ${body.length} ≠ ${events.length} 件`);
    const bad = [];
    body.slice(0, events.length).forEach((r, i) => {
      const e = events[i], line = i + 2;
      const diffs = [];
      if (r.length !== CSV_HEAD.length) diffs.push(`列数 ${r.length}`);
      if (common.normDate(r[0]) !== e.event_date) diffs.push(`日付 ${r[0]}≠${e.event_date}`);
      if (r[1] !== e.type) diffs.push(`種別 ${r[1]}≠${e.type}`);
      if (r[2] !== e.title) diffs.push("内容");
      if (common.normTime(r[3]) !== hhmm(e.start_time)) diffs.push(`開始 ${r[3]}≠${hhmm(e.start_time)}`);
      if (common.normTime(r[4]) !== hhmm(e.end_time)) diffs.push(`終了 ${r[4]}≠${hhmm(e.end_time)}`);
      if (r[5] !== e.note) diffs.push("備考");
      if (r[6] !== (e.is_published ? "公開" : "下書き")) diffs.push(`公開 ${r[6]}`);
      if (diffs.length) bad.push(`${line}行目 ${diffs.join(" / ")}`);
    });
    limited("[CSV内容]", bad);
  }

  // 種別 CSV
  let trows = null;
  try { trows = common.parseCSV(typesCsv); } catch (e) { err(`[種別CSV] 解析に失敗: ${e.message}`); }
  if (trows) {
    const tbody = trows.slice(1);
    if (tbody.length !== types.length) err(`[件数] 種別CSV の行数 ${tbody.length} ≠ ${types.length} 件`);
    const bad = [];
    tbody.slice(0, types.length).forEach((r, i) => {
      const t = types[i];
      if (r[0] !== t.name || r[1] !== t.color || r[2] !== String(t.sort_order)) bad.push(`${i + 2}行目 ${r.join(",")}`);
    });
    limited("[種別CSV内容]", bad);
  }

  // ---- 3. 形式（日付・時刻・種別の存在）----
  const typeNames = new Set(types.map(t => t.name));
  const fmt = [];
  events.forEach(e => {
    const id = `${e.event_date} ${e.type} ${e.title}`.trim();
    if (typeof e.event_date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(e.event_date) || common.normDate(e.event_date) !== e.event_date) fmt.push(`日付が不正: ${id}`);
    for (const k of ["start_time", "end_time"]) if (e[k] != null && !TIME_RE.test(e[k])) fmt.push(`${k === "start_time" ? "開始" : "終了"}時刻が不正「${e[k]}」: ${id}`);
    if (e.start_time && e.end_time && hhmm(e.end_time) < hhmm(e.start_time)) fmt.push(`終了が開始より前: ${id}`);
    if (!typeNames.has(e.type)) fmt.push(`種別「${e.type}」が event_types に存在しません: ${id}`);
  });
  limited("[形式]", fmt);
  const tfmt = [];
  types.forEach(t => { if (!COLOR_RE.test(t.color)) tfmt.push(`種別「${t.name}」の色が不正「${t.color}」`); });
  limited("[形式]", tfmt);

  // ---- 4. 直前のバックアップから半分以下に減っていないか ----
  if (prev) {
    for (const [k, label, n] of [["events", "events", events.length], ["event_types", "event_types", types.length]]) {
      if (prev[k] > 0 && n * 2 <= prev[k]) err(`[急減] ${label} が直前のバックアップ ${prev[k]} 件から ${n} 件へ半分以下に減っています`);
    }
  }
  return errs;
}
