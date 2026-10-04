// 相乗りの共通時刻の提案（public/js/pickup-common.js の suggestTime）のテスト。
// 実行: node --test scripts/pickup-common.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import vm from "node:vm";

const src = f => readFileSync(new URL(`../public/js/${f}`, import.meta.url), "utf8");
const { suggestTime } = vm.runInNewContext(`${src("common.js")}\n${src("pickup-common.js")}\n;({ suggestTime })`, {});
const plain = v => JSON.parse(JSON.stringify(v));

test("17:00 と 17:15・許容10分 → 17:05〜17:10、おすすめ 17:10", () => {
  assert.deepEqual(plain(suggestTime(["17:00", "17:15"])), { from: "17:05", to: "17:10", candidates: ["17:05", "17:10"], best: "17:10" });
});

test("希望が同じなら、その時刻を中心に前後の許容範囲", () => {
  const r = suggestTime(["18:00", "18:00"], { tolerance: 10 });
  assert.deepEqual(plain(r.candidates), ["17:50", "17:55", "18:00", "18:05", "18:10"]);
  assert.equal(r.best, "18:00");
});

test("3人：一番遅い希望 − 許容 〜 一番早い希望 ＋ 許容", () => {
  const r = suggestTime(["17:00", "17:10", "17:15"], { tolerance: 10 });
  assert.deepEqual(plain(r.candidates), ["17:05", "17:10"]);
});

test("離れすぎていると候補なし", () => {
  const r = suggestTime(["17:00", "17:30"], { tolerance: 10 });
  assert.deepEqual(plain(r.candidates), []);
  assert.equal(r.best, null);
  assert.equal(r.from, null);
});

test("送迎できる範囲（最終便など）で切る", () => {
  const r = suggestTime(["20:40", "20:45"], { tolerance: 10, window: ["16:00", "20:45"] });
  assert.deepEqual(plain(r.candidates), ["20:35", "20:40", "20:45"]);
  const early = suggestTime(["16:00", "16:05"], { tolerance: 10, window: ["16:00", "20:45"] });
  assert.deepEqual(plain(early.candidates), ["16:00", "16:05", "16:10"]);
});

test("ほかの便と走行時間が重なる候補は除く（車は1台）", () => {
  // 17:15 発の便（〜17:30）がある。この便も15分かかるので、17:01〜17:29 発は重なる
  const r = suggestTime(["17:00", "17:10"], { tolerance: 10, busy: [["17:15", "17:30"]], trip: 15 });
  assert.deepEqual(plain(r.candidates), ["17:00"]);
  assert.equal(r.best, "17:00");
});

test("刻みに合わない希望時刻でも、候補は刻みにそろえる", () => {
  const r = suggestTime(["17:03", "17:12"], { tolerance: 10, step: 5 });
  assert.deepEqual(plain(r.candidates), ["17:05", "17:10"]);
});
