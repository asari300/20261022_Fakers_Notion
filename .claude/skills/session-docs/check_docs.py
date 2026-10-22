#!/usr/bin/env python3
"""セッション文書と正典の文書を機械的に検査する。

  python3 -I .claude/skills/session-docs/check_docs.py          # リポジトリ全体
  python3 -I .claude/skills/session-docs/check_docs.py <root>   # ルートを指定

検査すること:
  1. スライド（doc/sessions/*/*.html。全体の slides.html と、トピック別の NN-<topic>.html）
     - <section class="slide" id="S01"> … が S01 から連番になっている
     - 外部参照（http:// / https:// / // で始まる src・href）が無い。オフラインで開くため
     - <style> 要素と style= 属性が無い。見た目は doc/assets/slides.css だけで決める
     - ../../assets/slides.css と ../../assets/slides.js を読んでいる
     - トピック別のデッキがあるセッションでは、slides.html が各デッキへリンクし、
       各デッキが slides.html へリンクしている（全体へ戻れるように）
  2. 相対リンク（Markdown と HTML）
     - 対象: README.md, CLAUDE.md, doc/**, log/**（log/local/ は除く）, src/*/README.md, .claude/skills/**
     - リンク先のファイルがある
     - `file.md#anchor` の anchor が、GitHub と同じ規則で作った見出しの anchor にある

ひとつでも失敗があれば終了コード 1。
"""

from __future__ import annotations

import re
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote

EXTERNAL = re.compile(r"^(?:[a-z][a-z0-9+.\-]*:|//)", re.I)       # http:, https:, mailto:, data:, //
MD_LINK = re.compile(r"(?<!!)\[[^\]]*\]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
MD_IMG = re.compile(r"!\[[^\]]*\]\(([^)\s]+)\)")
FENCE = re.compile(r"^(```|~~~).*?^\1", re.S | re.M)
INLINE_CODE = re.compile(r"`[^`\n]*`")


# --------------------------------------------------------------------------- スライド

class SlideParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.slide_ids: list[str] = []
        self.styles = 0
        self.style_attrs = 0
        self.external: list[str] = []
        self.refs: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        a = dict(attrs)
        if tag == "style":
            self.styles += 1
        if "style" in a:
            self.style_attrs += 1
        if tag == "section" and "slide" in (a.get("class") or "").split():
            self.slide_ids.append(a.get("id") or "")
        for key in ("src", "href"):
            v = a.get(key)
            if not v:
                continue
            if v.startswith(("http://", "https://", "//")):
                self.external.append(v)
            elif not v.startswith(("#", "mailto:", "data:")):
                self.refs.append(v)


def parse_deck(path: Path) -> SlideParser:
    p = SlideParser()
    p.feed(path.read_text(encoding="utf-8"))
    return p


def check_slides(path: Path) -> list[str]:
    p = parse_deck(path)
    errs = []
    want = [f"S{i:02d}" for i in range(1, len(p.slide_ids) + 1)]
    if not p.slide_ids:
        errs.append("slide が 0 枚")
    elif p.slide_ids != want:
        errs.append(f"slide の id が連番でない: {p.slide_ids}")
    if p.styles:
        errs.append(f"<style> が {p.styles} 個ある")
    if p.style_attrs:
        errs.append(f"style= 属性が {p.style_attrs} 個ある")
    if p.external:
        errs.append(f"外部参照が {len(p.external)} 件ある: {p.external[:3]}")
    for need in ("../../assets/slides.css", "../../assets/slides.js"):
        if need not in p.refs:
            errs.append(f"{need} を読んでいない")
    return errs


def check_topic_links(session: Path) -> list[str]:
    """全体の slides.html とトピック別のデッキ（NN-<topic>.html）が相互にリンクしているか。"""
    topics = sorted(session.glob("[0-9][0-9]-*.html"))
    overall = session / "slides.html"
    if not topics or not overall.exists():
        return []
    errs = []
    refs = {r.split("#", 1)[0] for r in parse_deck(overall).refs}
    errs += [f"slides.html から {t.name} へのリンクが無い" for t in topics if t.name not in refs]
    for t in topics:
        if "slides.html" not in {r.split("#", 1)[0] for r in parse_deck(t).refs}:
            errs.append(f"{t.name} から slides.html へ戻るリンクが無い")
    return errs


# --------------------------------------------------------------------------- リンク

def github_anchor(heading: str) -> str:
    """GitHub が見出しから作る anchor（英数字・空白・ハイフン以外を消し、空白をハイフンにする）。"""
    h = re.sub(r"<[^>]+>", "", heading).strip().lower()
    h = "".join(ch for ch in h if ch.isalnum() or ch in " -_")
    return h.replace(" ", "-")


def anchors_of(md: Path) -> set[str]:
    text = FENCE.sub("", md.read_text(encoding="utf-8"))
    out: set[str] = set()
    seen: dict[str, int] = {}
    for m in re.finditer(r"^#{1,6}\s+(.+?)\s*#*\s*$", text, re.M):
        base = github_anchor(m.group(1))
        n = seen.get(base, 0)
        out.add(base if n == 0 else f"{base}-{n}")
        seen[base] = n + 1
    return out


def links_in(path: Path) -> list[str]:
    text = path.read_text(encoding="utf-8")
    if path.suffix == ".md":
        text = INLINE_CODE.sub("", FENCE.sub("", text))
        return MD_LINK.findall(text) + MD_IMG.findall(text)
    p = SlideParser()
    p.feed(text)
    return p.refs


def check_links(root: Path, files: list[Path]) -> tuple[int, list[str]]:
    n, errs = 0, []
    for f in files:
        for raw in links_in(f):
            if EXTERNAL.match(raw) or raw.startswith("<"):
                continue
            target, _, anchor = unquote(raw).partition("#")
            dest = (f.parent / target).resolve() if target else f.resolve()
            n += 1
            rel = f.relative_to(root).as_posix()
            if not dest.exists():
                errs.append(f"{rel} -> {raw}（ファイルが無い）")
                continue
            if anchor and dest.suffix == ".md" and anchor not in anchors_of(dest):
                errs.append(f"{rel} -> {raw}（見出しが無い）")
    return n, errs


def doc_files(root: Path) -> list[Path]:
    files = [root / "README.md", root / "CLAUDE.md"]
    for pat in ("doc/**/*.md", "doc/**/*.html", "log/**/*.md", "src/*/README.md", ".claude/skills/**/*.md"):
        files += root.glob(pat)
    return sorted({f for f in files
                   if f.is_file() and "log/local" not in f.as_posix() and "log/sessions/" not in f.as_posix()})


# --------------------------------------------------------------------------- 実行

def main(argv: list[str]) -> int:
    root = Path(argv[0]).resolve() if argv else Path.cwd()
    failed = False

    decks = sorted(root.glob("doc/sessions/*/*.html"))
    for deck in decks:
        errs = check_slides(deck)
        rel = deck.relative_to(root).as_posix()
        print(f"[slides] {rel}: {'OK' if not errs else 'NG'}")
        for e in errs:
            print(f"    {e}")
        failed |= bool(errs)
    for session in sorted({d.parent for d in decks}):
        errs = check_topic_links(session)
        if errs:
            print(f"[topics] {session.relative_to(root).as_posix()}: NG")
            for e in errs:
                print(f"    {e}")
        failed |= bool(errs)

    files = doc_files(root)
    n, errs = check_links(root, files)
    print(f"[links] 文書 {len(files)} 件 / 相対リンク {n} 件 / 切れ {len(errs)} 件")
    for e in errs[:40]:
        print(f"    {e}")
    failed |= bool(errs)

    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
