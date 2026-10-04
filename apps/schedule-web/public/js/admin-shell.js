"use strict";
// 管理画面の枠：狭い画面では、サイドバーを ☰ で開け閉めする。

(() => {
  const shell = $("app"), btn = $("menu-toggle"), scrim = $("scrim");
  const setOpen = open => {
    shell.classList.toggle("menu-open", open);
    btn.setAttribute("aria-expanded", String(open));
    btn.setAttribute("aria-label", open ? "メニューを閉じる" : "メニューを開く");
    scrim.hidden = !open;
  };
  btn.addEventListener("click", () => setOpen(!shell.classList.contains("menu-open")));
  scrim.addEventListener("click", () => setOpen(false));
  $("tabs").addEventListener("click", e => { if (e.target.closest("button")) setOpen(false); });   // ページを選んだら閉じる
  document.addEventListener("keydown", e => { if (e.key === "Escape" && shell.classList.contains("menu-open")) setOpen(false); });
})();
