// 検証ロジックのテスト。「わざと壊したデータで、検証が失敗すること」を確認する。
// 実行: node --test scripts/backup.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import http from "node:http";
import { execFile } from "node:child_process";
import { mkdtemp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { buildFiles, loadCommon, verifyBackup } from "./backup-lib.mjs";

const common = loadCommon();
const SCRIPT = fileURLToPath(new URL("./backup.mjs", import.meta.url));

const TYPES = [
  { name: "高1授業", color: "#2a6fdb", sort_order: 1 },
  { name: "休講", color: "#b3273a", sort_order: 2 },
];
const EVENTS = [
  { id: "1", event_date: "2027-01-05", type: "高1授業", title: "高1授業", start_time: "18:30:00", end_time: "21:40:00", note: "", is_published: true },
  { id: "2", event_date: "2027-01-06", type: "高1授業", title: " 前後に空白 ", start_time: "18:30:00", end_time: null, note: 'カンマ,"引用符"\n改行あり', is_published: true },
  { id: "3", event_date: "2027-01-29", type: "休講", title: "休講", start_time: null, end_time: null, note: "", is_published: true },
];

// 正常なパイプラインを組み、上書きしたい部分だけ差し替えて検証する
function check({ events = EVENTS, types = TYPES, dbCounts, tamper = f => f, prev = null } = {}) {
  const files = tamper(buildFiles(events, types, "2026-01-01T00:00:00.000Z"));
  return verifyBackup({
    events, types,
    dbCounts: dbCounts ?? { events: events.length, event_types: types.length },
    ...files, prev, common,
  });
}
const has = (errs, text) => assert.ok(errs.some(e => e.includes(text)), `「${text}」を含むエラーが出るはず。実際: ${JSON.stringify(errs)}`);

// ---------------- 単体（検証関数）----------------
test("正常データは合格（引用符・カンマ・改行・前後の空白を含んでも往復できる）", () => {
  assert.deepEqual(check(), []);
});

test("1. DB の総件数と取得件数が違えば失敗", () => {
  has(check({ dbCounts: { events: 4, event_types: 2 } }), "DB の総数 4 件");
  has(check({ dbCounts: { events: 3, event_types: 5 } }), "event_types: DB の総数 5 件");
});

test("1. JSON の件数・中身が違えば失敗", () => {
  const edit = fn => f => { const j = JSON.parse(f.json); fn(j); return { ...f, json: JSON.stringify(j) }; };
  has(check({ tamper: edit(j => { j.counts.events = 99; }) }), "counts.events = 99");
  has(check({ tamper: edit(j => { j.events.pop(); }) }), "JSON の events 配列 2 件");
  has(check({ tamper: edit(j => { j.events[0].title = "改ざん"; }) }), "JSON の events が元データと一致しません");
  has(check({ tamper: f => ({ ...f, json: "{壊れたJSON" }) }), "JSON として読み込めません");
});

test("1・2. CSV の行が欠けたら失敗", () => {
  const dropLast = f => { const lines = f.csv.trimEnd().split("\r\n"); lines.pop(); return { ...f, csv: lines.join("\r\n") + "\r\n" }; };
  has(check({ tamper: dropLast }), "CSV の行数 2");
});

test("2. CSV の内容が元データと違えば失敗", () => {
  has(check({ tamper: f => ({ ...f, csv: f.csv.replace('"休講","休講"', '"休講","改ざん"') }) }), "内容");
  has(check({ tamper: f => ({ ...f, csv: f.csv.replace("2027-01-06", "2027-01-07") }) }), "日付");
  has(check({ tamper: f => ({ ...f, csv: f.csv.replace('"18:30","21:40"', '"18:30","21:41"') }) }), "終了");
  has(check({ tamper: f => ({ ...f, csv: f.csv.replace('"日付"', '"日にち"') }) }), "見出し行");
});

test("2. 種別CSV が違えば失敗", () => {
  has(check({ tamper: f => ({ ...f, typesCsv: f.typesCsv.replace("#2a6fdb", "#000000") }) }), "種別CSV内容");
});

test("3. 日付・時刻・時刻の前後の形式エラーで失敗", () => {
  const bad = patch => EVENTS.map((e, i) => (i === 0 ? { ...e, ...patch } : e));
  has(check({ events: bad({ event_date: "2027-02-30" }) }), "日付が不正");
  has(check({ events: bad({ event_date: "2027/01/05" }) }), "日付が不正");
  has(check({ events: bad({ start_time: "25:00:00" }) }), "開始時刻が不正");
  has(check({ events: bad({ end_time: "9:5" }) }), "終了時刻が不正");
  has(check({ events: bad({ start_time: "21:00:00", end_time: "18:00:00" }) }), "終了が開始より前");
});

test("3. events.type が event_types に無ければ失敗 / 色の形式不正も失敗", () => {
  has(check({ events: EVENTS.map((e, i) => (i === 2 ? { ...e, type: "存在しない種別" } : e)) }), "event_types に存在しません");
  has(check({ types: TYPES.map((t, i) => (i === 0 ? { ...t, color: "red" } : t)) }), "色が不正");
});

test("0 件は失敗", () => {
  has(check({ events: [] }), "events が 0 件");
  has(check({ types: [] }), "event_types が 0 件");
});

test("4. 直前のバックアップの半分以下に減ったら失敗（半分より多ければ合格）", () => {
  has(check({ prev: { events: 6, event_types: 2 } }), "半分以下");   // 3 <= 6/2
  has(check({ prev: { events: 100, event_types: 2 } }), "半分以下");
  assert.deepEqual(check({ prev: { events: 5, event_types: 2 } }), []); // 3 > 2.5
  has(check({ prev: { events: 3, event_types: 10 } }), "event_types");
});

// ---------------- 通し（偽の Supabase サーバー + backup.mjs 本体）----------------
function startServer({ events = EVENTS, types = TYPES, countLie } = {}) {
  const tables = { events, event_types: types };
  const server = http.createServer((req, res) => {
    const u = new URL(req.url, "http://x");
    const name = u.pathname.split("/").pop();
    const rows = tables[name];
    if (!rows) { res.writeHead(404).end("{}"); return; }
    const [a, b] = (req.headers.range || "0-999").split("-").map(Number);
    const slice = rows.slice(a, b + 1);
    const total = countLie?.[name] ?? rows.length;
    res.writeHead(200, {
      "content-type": "application/json",
      "content-range": slice.length ? `${a}-${a + slice.length - 1}/${total}` : `*/${total}`,
    });
    res.end(JSON.stringify(slice));
  });
  return new Promise(r => server.listen(0, "127.0.0.1", () => r({ server, url: `http://127.0.0.1:${server.address().port}` })));
}

const runBackup = (out, url) => new Promise(resolve =>
  execFile(process.execPath, [SCRIPT, "--out", out], { env: { ...process.env, SUPABASE_URL: url, SUPABASE_ANON_KEY: "test-key" } },
    (err, stdout, stderr) => resolve({ code: err ? err.code : 0, stdout, stderr })));

async function snapshot(dir) {
  const out = {};
  for (const f of (await readdir(dir).catch(() => [])).sort()) out[f] = await readFile(join(dir, f), "utf8");
  return out;
}

// 既存のバックアップ（2025-12-01）を置いた保存先を作る
async function makeOut(prevEvents = 3) {
  const dir = await mkdtemp(join(tmpdir(), "bk-test-"));
  await mkdir(dir, { recursive: true });
  await writeFile(join(dir, "backup-2025-12-01.json"), JSON.stringify({ counts: { events: prevEvents, event_types: 2 }, marker: "既存" }));
  await writeFile(join(dir, "backup-2025-12-01.csv"), "既存のCSV");
  return dir;
}

async function scenario(name, serverOpts, { prevEvents = 3, expectCode, expectText }) {
  test(`通し: ${name}`, async () => {
    const { server, url } = await startServer(serverOpts);
    const out = await makeOut(prevEvents);
    try {
      const before = await snapshot(out);
      const r = await runBackup(out, url);
      assert.equal(r.code, expectCode, `終了コード（stderr: ${r.stderr}）`);
      if (expectText) assert.ok(r.stderr.includes(expectText), `stderr に「${expectText}」: ${r.stderr}`);
      const after = await snapshot(out);
      if (expectCode !== 0) assert.deepEqual(after, before, "失敗時は既存のバックアップが1バイトも変わらない（新規ファイルも作られない）");
      else assert.ok(Object.keys(after).length === Object.keys(before).length + 3, "成功時は3ファイルが追加される");
    } finally { server.close(); await rm(out, { recursive: true, force: true }); }
  });
}

await scenario("正常データ → 成功して3ファイル追加", {}, { expectCode: 0 });
await scenario("DB の総件数と取得件数が食い違う → 失敗・既存は無傷", { countLie: { events: 99 } }, { expectCode: 1, expectText: "DB の総数 99 件" });
await scenario("events.type が存在しない種別 → 失敗・既存は無傷", { events: EVENTS.map((e, i) => (i === 0 ? { ...e, type: "幽霊種別" } : e)) }, { expectCode: 1, expectText: "event_types に存在しません" });
await scenario("時刻が不正 → 失敗・既存は無傷", { events: EVENTS.map((e, i) => (i === 0 ? { ...e, start_time: "99:99:00" } : e)) }, { expectCode: 1, expectText: "開始時刻が不正" });
await scenario("直前(100件)から半分以下(3件)に急減 → 失敗・既存は無傷", {}, { prevEvents: 100, expectCode: 1, expectText: "半分以下" });
await scenario("events が 0 件 → 失敗・既存は無傷", { events: [] }, { expectCode: 1, expectText: "0 件" });
