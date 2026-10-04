// 共通ナビ（public/js/nav-config.js）の定義のテスト。
// 実行: node --test scripts/nav.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, existsSync } from "node:fs";
import vm from "node:vm";

const read = f => readFileSync(new URL(`../public/${f}`, import.meta.url), "utf8");
const load = () => vm.runInNewContext(`${read("js/nav-config.js")}\n;({ JUKU_DESK_URL, NAV_GROUPS, navGroups, navCurrentKey })`, {});
const plain = v => JSON.parse(JSON.stringify(v));
const { navGroups, navCurrentKey, NAV_GROUPS } = load();

test("juku-desk の URL は 1 つの定数で、リンク先は <URL>+パスになる（末尾の / は取る）", () => {
  const groups = plain(navGroups("https://juku.example.com/", "/index.html"));
  assert.deepEqual(groups[0].items.map(i => i.href), [
    "https://juku.example.com/students", "https://juku.example.com/tools/pdf_splitter/jobs",
    "https://juku.example.com/print", "https://juku.example.com/quizzes/new",
  ]);
  assert.deepEqual(groups[0].items.map(i => i.label), ["生徒データベース", "PDF分割", "印刷", "小テスト作成"]);
});

test("URL が空・不正なら juku-desk のグループは出さない", () => {
  for (const bad of ["", "  ", undefined, null, "javascript:alert(1)", "juku.example.com", "ftp://x.example.com"]) {
    const groups = plain(navGroups(bad, "/index.html"));
    assert.deepEqual(groups.map(g => g.label), ["スケジュール"], `base=${JSON.stringify(bad)}`);
  }
});

test("schedule-web の並びは index / admin / pickup", () => {
  const sched = plain(navGroups("https://juku.example.com", "/")).at(-1);
  assert.deepEqual(sched.items.map(i => i.href), ["index.html", "admin.html", "pickup.html"]);
  assert.deepEqual(sched.items.map(i => i.label), ["年間スケジュール", "管理画面", "生徒ページ"]);
});

test("今のページの項目だけ current になる", () => {
  const cur = p => plain(navGroups("https://juku.example.com", p)).flatMap(g => g.items).filter(i => i.current).map(i => i.href);
  assert.deepEqual(cur("/"), ["index.html"]);
  assert.deepEqual(cur("/index.html"), ["index.html"]);
  assert.deepEqual(cur("/admin.html"), ["admin.html"]);
  assert.deepEqual(cur("/admin"), ["admin.html"]);
  assert.deepEqual(cur("/pickup"), ["pickup.html"]);
  assert.deepEqual(cur("/pickup-respond.html"), []);
  assert.equal(navCurrentKey("/unknown.html"), null);
});

test("juku-desk の URL がどこにもハードコードされていない（nav-config.js の JUKU_DESK_URL だけ）", () => {
  const { JUKU_DESK_URL } = load();
  assert.equal(JUKU_DESK_URL, "", "コミットする値は空のまま（本番の URL は人間が入れる）か、公開してよい URL にする");
  for (const f of ["admin.html", "js/unified-nav.js", "js/nav-config.js"]) {
    assert.doesNotMatch(read(f).replace(/\/\/.*$/gm, ""), /onrender\.com|juku-desk\.[a-z]+/i, f);
  }
});

test("schedule-web のリンク先のファイルが実在する", () => {
  const sched = NAV_GROUPS.find(g => g.site === "schedule-web");
  for (const it of sched.items) assert.ok(existsSync(new URL(`../public/${it.path}`, import.meta.url)), it.path);
});

test("ナビは管理画面（講師・事務向け）だけに置く。保護者・生徒向けの index / pickup / pickup-respond には出さない", () => {
  const admin = read("admin.html");
  assert.match(admin, /css\/unified-nav\.css/);
  const a = admin.indexOf('<script src="js/nav-config.js"></script>'), b = admin.indexOf('<script src="js/unified-nav.js"></script>');
  assert.ok(a !== -1 && b > a, "admin.html: nav-config.js → unified-nav.js の順");
  for (const f of ["index.html", "pickup.html", "pickup-respond.html"]) {
    assert.doesNotMatch(read(f), /unified-nav|nav-config|id="unified-nav"/, `${f} にナビが入っている`);
  }
});

test("管理画面は既存のサイドバーの中に置き場（#unified-nav）がある", () => {
  assert.match(read("admin.html"), /<div id="unified-nav" data-variant="embedded">/);
});

test("ナビの JS は innerHTML を使わず、外部リンクに target を付けない", () => {
  const js = read("js/unified-nav.js").replace(/\/\/.*$/gm, ""); // コメントは除く
  assert.doesNotMatch(js, /innerHTML|outerHTML|insertAdjacentHTML|document\.write/);
  assert.doesNotMatch(js, /target/);
});

test("juku-desk の iframe の中（window.self !== window.top）ではナビを出さない。直接開いたときは出す", () => {
  const run = embedded => {
    let removed = false, appended = false;
    const mount = { remove: () => { removed = true; }, append: () => { appended = true; } };
    const node = () => ({ setAttribute() {}, append() {}, classList: { add() {} } });
    const self = {};
    vm.runInNewContext(read("js/nav-config.js") + "\n" + read("js/unified-nav.js"), {
      window: { self, top: embedded ? {} : self }, location: { pathname: "/admin" },
      document: { getElementById: () => mount, createElement: node },
    });
    return { removed, appended };
  };
  assert.deepEqual(run(true), { removed: true, appended: false });
  assert.deepEqual(run(false), { removed: false, appended: true });
});
