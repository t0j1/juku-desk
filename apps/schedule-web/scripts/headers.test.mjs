// public/_headers（Cloudflare Pages のレスポンスヘッダ）のテスト。
// 実行: node --test scripts/headers.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

// "/path\n  Name: value\n..." のブロックを { path: { name: value } } にする
const parse = text => {
  const rules = {};
  let current = null;
  for (const raw of text.split("\n")) {
    if (!raw.trim() || raw.trim().startsWith("#")) continue;
    if (/^\S/.test(raw)) { current = raw.trim(); rules[current] ??= {}; continue; }
    const [name, ...value] = raw.trim().split(":");
    rules[current][name.trim().toLowerCase()] = value.join(":").trim();
  }
  return rules;
};
const rules = parse(readFileSync(new URL("../public/_headers", import.meta.url), "utf8"));

test("全ページ: juku-desk（と同一オリジン）からの埋め込みだけを許す", () => {
  assert.equal(rules["/*"]["content-security-policy"], "frame-ancestors 'self' https://juku-desk.onrender.com");
  assert.equal(rules["/*"]["x-content-type-options"], "nosniff");
});

test("/admin.html に X-Frame-Options: DENY はない（CSP が役割を引き継ぐ）。noindex は残す", () => {
  assert.equal(rules["/admin.html"]["x-frame-options"], undefined);
  assert.equal(rules["/admin.html"]["x-robots-tag"], "noindex, nofollow");
});

test("埋め込む 3 ページ（/、/admin、/pickup）に X-Frame-Options はない", () => {
  for (const path of ["/*", "/admin.html", "/admin", "/pickup.html", "/pickup"]) {
    assert.equal(rules[path]?.["x-frame-options"], undefined, path);
  }
});

test("/admin と /pickup（.html なしの URL）も noindex", () => {
  for (const path of ["/admin", "/pickup"]) assert.equal(rules[path]["x-robots-tag"], "noindex, nofollow", path);
});

test("pickup-respond.html は埋め込まない（DENY のまま）", () => {
  assert.equal(rules["/pickup-respond.html"]["x-frame-options"], "DENY");
});
