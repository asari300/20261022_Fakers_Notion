/*
 * Fakers Notion セッションスライドの共通スクリプト。外部ライブラリに依存しない。
 *
 * 操作: ← → / PageUp PageDown / Space / Home End で移動、#S05 で直接開く、
 *       p で一覧表示、t でライト／ダーク切り替え、スワイプでも移動できる。
 * 各 <section class="slide"> にフッター（デッキ名と「n / 全体」）を自動で入れる。
 */
(() => {
  "use strict";

  const slides = Array.from(document.querySelectorAll("section.slide"));
  if (slides.length === 0) return;

  const deckName = document.body.dataset.deck || document.title;
  let index = 0;

  // ------------------------------------------------------------ 部品を組み立てる
  const deck = document.createElement("div");
  deck.className = "deck";
  slides[0].before(deck);
  slides.forEach((s, i) => {
    deck.append(s);
    if (!s.querySelector(".foot")) {
      const foot = document.createElement("div");
      foot.className = "foot";
      const left = document.createElement("span");
      left.textContent = deckName;
      const right = document.createElement("span");
      right.textContent = `${i + 1} / ${slides.length}`;
      foot.append(left, right);
      s.append(foot);
    }
    s.addEventListener("click", () => {
      if (document.body.classList.contains("overview")) {
        toggleOverview(false);
        show(i);
      }
    });
  });

  const progress = document.createElement("div");
  progress.className = "progress";
  document.body.append(progress);

  const ctl = document.createElement("div");
  ctl.className = "ctl";
  const button = (label, title, fn) => {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = label;
    b.title = title;
    b.addEventListener("click", fn);
    ctl.append(b);
  };
  button("◀", "前へ (←)", () => show(index - 1));
  button("▶", "次へ (→)", () => show(index + 1));
  button("▦", "一覧 (p)", () => toggleOverview());
  button("◐", "ライト／ダーク (t)", () => toggleTheme());
  document.body.append(ctl);

  // ------------------------------------------------------------ 表示
  function show(i, updateHash = true) {
    index = Math.max(0, Math.min(slides.length - 1, i));
    slides.forEach((s, k) => s.classList.toggle("on", k === index));
    progress.style.width = `${((index + 1) / slides.length) * 100}%`;
    if (updateHash && slides[index].id) {
      history.replaceState(null, "", `#${slides[index].id}`);
    }
  }

  function fromHash() {
    const id = decodeURIComponent(location.hash.slice(1));
    const k = slides.findIndex((s) => s.id === id);
    return k >= 0 ? k : 0;
  }

  function toggleOverview(force) {
    const on = document.body.classList.toggle("overview", force);
    if (on) slides[index].scrollIntoView({ block: "center" });
  }

  function toggleTheme() {
    const root = document.documentElement;
    const dark = root.dataset.theme
      ? root.dataset.theme === "dark"
      : matchMedia("(prefers-color-scheme: dark)").matches;
    root.dataset.theme = dark ? "light" : "dark";
  }

  // ------------------------------------------------------------ 操作
  document.addEventListener("keydown", (e) => {
    if (e.altKey || e.ctrlKey || e.metaKey) return;
    switch (e.key) {
      case "ArrowRight": case "PageDown": case " ": show(index + 1); break;
      case "ArrowLeft": case "PageUp": show(index - 1); break;
      case "Home": show(0); break;
      case "End": show(slides.length - 1); break;
      case "p": toggleOverview(); break;
      case "t": toggleTheme(); break;
      case "Escape": toggleOverview(false); break;
      default: return;
    }
    e.preventDefault();
  });

  let touchX = null;
  // 図・表・コードの上のスワイプは横スクロールに使うので、ページ送りにしない
  document.addEventListener("touchstart", (e) => {
    touchX = e.target.closest("svg.fig, pre, table") ? null : e.touches[0].clientX;
  }, { passive: true });
  document.addEventListener("touchend", (e) => {
    if (touchX === null) return;
    const dx = e.changedTouches[0].clientX - touchX;
    if (Math.abs(dx) > 60) show(index + (dx < 0 ? 1 : -1));
    touchX = null;
  }, { passive: true });

  window.addEventListener("hashchange", () => show(fromHash(), false));
  window.addEventListener("beforeprint", () => toggleOverview(false));

  show(fromHash(), false);
})();
