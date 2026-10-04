"use strict";
// 共通ナビを描く（定義は nav-config.js）。依存なし。
// 管理画面（講師・事務向け）の <div id="unified-nav"> に入れる。保護者・生徒向けの index / pickup には置かない

(() => {
  const el = (tag, attrs = {}, text) => {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
    if (text) node.textContent = text;
    return node;
  };

  const mount = document.getElementById("unified-nav");
  if (!mount) return;

  const groups = navGroups(JUKU_DESK_URL, location.pathname);
  const nav = el("nav", { class: "unav-nav", "aria-label": "アプリの切り替え" });
  groups.forEach(g => {
    const box = el("div", { class: "unav-group", role: "group", "aria-label": g.label });
    box.append(el("p", { class: "unav-label" }, g.label));
    g.items.forEach(it => {
      const a = el("a", { class: "unav-link", href: it.href }, it.label);   // 同じタブで開く（target は付けない）
      if (it.current) { a.classList.add("is-current"); a.setAttribute("aria-current", "page"); }
      box.append(a);
    });
    nav.append(box);
  });

  mount.append(nav);
})();
