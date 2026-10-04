"use strict";
// 共通ナビを描く（定義は nav-config.js）。依存なし。
//   <div id="unified-nav" data-variant="embedded"> があれば、そこに入れる（管理画面のサイドバーの中）
//   無ければ、左端に固定のサイドバーを作る（768px 未満は ☰ で開閉）

(() => {
  const el = (tag, attrs = {}, text) => {
    const node = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
    if (text) node.textContent = text;
    return node;
  };

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

  const mount = document.getElementById("unified-nav");
  if (mount) { mount.append(nav); return; }

  // 単独のページ：左端のサイドバー + スマホ幅の ☰
  const side = el("aside", { class: "unav", id: "unav" });
  const close = el("button", { type: "button", class: "unav-close", "aria-label": "メニューを閉じる" }, "✕ 閉じる");
  side.append(close, el("p", { class: "unav-brand" }, "碩学館"), nav);
  const toggle = el("button", { type: "button", class: "unav-toggle", "aria-controls": "unav", "aria-expanded": "false", "aria-label": "メニューを開く" }, "☰");
  const scrim = el("div", { class: "unav-scrim", hidden: "" });
  document.body.classList.add("has-unav");
  document.body.append(toggle, scrim, side);

  const setOpen = open => {
    side.classList.toggle("is-open", open);
    scrim.hidden = !open;
    toggle.setAttribute("aria-expanded", String(open));
  };
  toggle.addEventListener("click", () => setOpen(!side.classList.contains("is-open")));
  close.addEventListener("click", () => setOpen(false));
  scrim.addEventListener("click", () => setOpen(false));
  document.addEventListener("keydown", e => { if (e.key === "Escape") setOpen(false); });
  window.matchMedia("(min-width: 768px)").addEventListener("change", e => { if (e.matches) setOpen(false); });
})();
