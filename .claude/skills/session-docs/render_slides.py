#!/usr/bin/env python3
"""スライドを実際のブラウザ（Playwright の Chromium）で開いて検査する。

  uv run python .claude/skills/session-docs/render_slides.py                  # 全デッキ（doc/sessions/*/*.html）
  uv run python .claude/skills/session-docs/render_slides.py <deck.html>…    # 指定したデッキ
  オプション: --out <dir>（スクリーンショットの置き場。既定は log/local/render/。コミットしない）

検査すること（file:// で開く。外部への通信は無い前提）:
  1. コンソールのエラーと、ページ内の例外が 0 件
  2. デスクトップ（1600x900）のライトとダークで、どのスライドも縦にも横にもはみ出さない
     （スライドの中でスクロールが要る＝発表で見切れる）。フッターのページ番号が操作ボタンに隠れない
  3. スマートフォン（390x844）で、ページ全体が横にはみ出さない。縦のスクロールは許す
  4. → キーで次のスライドに進み、URL のハッシュが #S02 になる。#S03 を開くと 3 枚目が出る
  5. 各スライドのスクリーンショットを残す（目で確かめるため）

ひとつでも失敗があれば終了コード 1。
初回は `uv run playwright install chromium` が要る。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

ROOT = Path(__file__).resolve().parents[3]
VIEWS = [
    ("desktop-light", {"width": 1600, "height": 900}, "light", True),
    ("desktop-dark", {"width": 1600, "height": 900}, "dark", True),
    ("mobile", {"width": 390, "height": 844}, "light", False),
]

MEASURE = """() => {
  const s = document.querySelector('section.slide.on');
  if (!s) return null;
  const r = s.getBoundingClientRect();
  let wide = [];
  for (const el of s.querySelectorAll('table, pre, svg, .card, .cols-2, .cols-3, img')) {
    const b = el.getBoundingClientRect();
    if (b.right > r.right + 1 || b.left < r.left - 1) wide.push(el.tagName.toLowerCase() + (el.className ? '.' + String(el.className.baseVal ?? el.className).split(' ')[0] : ''));
  }
  return {
    id: s.id,
    vOver: s.scrollHeight - s.clientHeight,
    hOver: s.scrollWidth - s.clientWidth,
    pageH: document.documentElement.scrollWidth - document.documentElement.clientWidth,
    wide: wide.slice(0, 3),
    footHidden: (() => {
      const num = s.querySelector('.foot span:last-child'), ctl = document.querySelector('.ctl');
      if (!num || !ctl) return false;
      const a = num.getBoundingClientRect(), b = ctl.getBoundingClientRect();
      return a.right > b.left && a.left < b.right && a.bottom > b.top && a.top < b.bottom;
    })(),
  };
}"""


def check_deck(browser, deck: Path, out: Path) -> list[str]:
    errs: list[str] = []
    url = deck.resolve().as_uri()
    rel = deck.resolve().relative_to(ROOT).as_posix()
    name = f"{deck.parent.name}/{deck.stem}"            # トピック別のデッキと置き場がぶつからないように

    for view, size, scheme, strict in VIEWS:
        ctx = browser.new_context(viewport=size, color_scheme=scheme, device_scale_factor=1)
        page = ctx.new_page()
        problems: list[str] = []
        page.on("console", lambda m: problems.append(f"console.{m.type}: {m.text}") if m.type == "error" else None)
        page.on("pageerror", lambda e: problems.append(f"pageerror: {e}"))
        page.goto(url)
        page.wait_for_load_state("load")
        n = page.locator("section.slide").count()
        shot_dir = out / name / view
        shot_dir.mkdir(parents=True, exist_ok=True)

        for i in range(1, n + 1):
            sid = f"S{i:02d}"
            page.evaluate(f"location.hash = '#{sid}'")
            page.wait_for_timeout(60)
            m = page.evaluate(MEASURE)
            if not m or m["id"] != sid:
                errs.append(f"{rel} [{view}] #{sid} を開けない（表示中: {m and m['id']}）")
                continue
            if strict and (m["vOver"] > 2 or m["hOver"] > 2):
                errs.append(f"{rel} [{view}] {sid} がはみ出す（縦 {m['vOver']}px / 横 {m['hOver']}px）{m['wide']}")
            if m["footHidden"]:
                errs.append(f"{rel} [{view}] {sid} のページ番号が操作ボタンに隠れる")
            if not strict and m["pageH"] > 2:
                errs.append(f"{rel} [{view}] {sid} でページが横にはみ出す（{m['pageH']}px）{m['wide']}")
            page.screenshot(path=str(shot_dir / f"{sid}.png"))

        if view == "desktop-light":
            page.evaluate("location.hash = '#S01'")
            page.wait_for_timeout(60)
            page.keyboard.press("ArrowRight")
            page.wait_for_timeout(60)
            if not page.url.endswith("#S02"):
                errs.append(f"{rel} → キーで #S02 に進まない（{page.url.rsplit('/', 1)[-1]}）")
            page.goto(url + "#S03")
            page.wait_for_timeout(100)
            if page.evaluate("document.querySelector('section.slide.on')?.id") != "S03":
                errs.append(f"{rel} #S03 で開いても 3 枚目が出ない")

        errs += [f"{rel} [{view}] {p}" for p in problems]
        print(f"[render] {rel} [{view}] {n} 枚 → {shot_dir.relative_to(ROOT) if shot_dir.is_relative_to(ROOT) else shot_dir}")
        ctx.close()
    return errs


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("decks", nargs="*")
    ap.add_argument("--out", default=str(ROOT / "log" / "local" / "render"))
    args = ap.parse_args(argv)

    decks = [Path(d) for d in args.decks] or sorted(ROOT.glob("doc/sessions/*/*.html"))
    out = Path(args.out).resolve()
    errs: list[str] = []
    with sync_playwright() as p:
        browser = p.chromium.launch()
        for deck in decks:
            errs += check_deck(browser, deck, out)
        browser.close()

    print(f"[render] デッキ {len(decks)} 件 / 問題 {len(errs)} 件")
    for e in errs:
        print(f"    {e}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
