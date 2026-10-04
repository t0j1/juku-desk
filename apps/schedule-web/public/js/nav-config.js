"use strict";
// 2 つのアプリ（juku-desk / schedule-web）を行き来するナビの定義。
// 並びと名前は juku-desk 側の config/navigation.yml とそろえる（変えるときは両方）。

// juku-desk の URL。リンク先はここだけで決める（例: "https://<app>.onrender.com"）。
// 空のままなら juku-desk のグループは出さない（このアプリのリンクだけ出る）。
const JUKU_DESK_URL = "";

const NAV_GROUPS = [
  { label: "塾日報ステーション", site: "juku-desk", items: [
    { label: "生徒データベース", path: "/students" },
    { label: "PDF分割", path: "/tools/pdf_splitter/jobs" },
    { label: "印刷", path: "/print" },
    { label: "小テスト作成", path: "/quizzes/new" },
  ] },
  { label: "スケジュール", site: "schedule-web", items: [
    { key: "index", label: "年間スケジュール", path: "index.html" },
    { key: "admin", label: "管理画面", path: "admin.html" },
    { key: "pickup", label: "生徒ページ", path: "pickup.html" },
  ] },
];

// base: juku-desk の URL（http(s) 以外・空は無効）。pathname: 今のページのパス
function navGroups(base, pathname) {
  const root = /^https?:\/\/[^\s/]+/i.test(String(base || "").trim()) ? String(base).trim().replace(/\/+$/, "") : "";
  const current = navCurrentKey(pathname);
  return NAV_GROUPS
    .filter(g => g.site !== "juku-desk" || root)
    .map(g => ({
      label: g.label,
      items: g.items.map(it => ({
        label: it.label,
        href: g.site === "juku-desk" ? root + it.path : it.path,
        current: g.site === "schedule-web" && it.key === current,
      })),
    }));
}

// "/", "/index.html" → index、"/admin" "/admin.html" → admin、"/pickup" "/pickup.html" → pickup
function navCurrentKey(pathname) {
  const name = String(pathname || "/").split("/").filter(Boolean).pop() || "index";
  const key = name.replace(/\.html$/i, "");
  return ["index", "admin", "pickup"].includes(key) ? key : null;
}
