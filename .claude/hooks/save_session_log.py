#!/usr/bin/env python3
"""Claude Code のセッション記録を `log/local/` に保存する。

`.claude/settings.json` の Stop / SessionEnd フックから呼ばれる。
標準入力にフックの JSON が来るので、そこから transcript のパスを取り出す。

出力は2つ（どちらも git 管理外の log/local/ に置く）。
  log/local/<日付>-<セッションID>.md          読むための整形版。**伏せ字済み**
  log/local/raw/<日付>-<セッションID>.jsonl.gz 完全な生ログ（圧縮）。伏せ字なし

公開リポジトリにコミットするのは整形版だけ。finish-session スキルが
log/local/ から worktree の log/sessions/ にコピーし、`--check` で取りこぼしを検査してからコミットする。
生ログにはメールアドレスやローカルパスがそのまま入っているので、絶対にコミットしない。

元は兄弟リポジトリ 20260816_exam の同名スクリプト。違いは次のとおり。
  - 出力先が log/local/
  - 整形版を伏せ字にする（redact）
  - project slug を CLAUDE_PROJECT_DIR から求める（worktree から手動で実行しても元の transcript が見つかる）
  - 手動実行用の引数（--session / --transcript / --latest [--match] / --out / --check）

フックとして呼ばれたときは、失敗しても黙って終了する（終了コードは常に0）。
ログ取りが本作業を止めてはいけない。`--check` だけは、取りこぼしがあれば 1 を返す。
"""

from __future__ import annotations

import argparse
import getpass
import gzip
import json
import os
import re
import shutil
import sys
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]      # .claude/hooks/x.py -> リポジトリ（または worktree）のルート
DEFAULT_OUT = ROOT / "log" / "local"

# 本文をそのまま載せると巨大になるツール結果の上限
MAX_RESULT_CHARS = 800
MAX_TOOL_INPUT_CHARS = 600


# --------------------------------------------------------------------------- 伏せ字

def _local_names() -> set[str]:
    """伏せ字にするローカルのユーザー名。ホームディレクトリ名とログイン名。"""
    names = {Path.home().name}
    try:
        names.add(getpass.getuser())
    except Exception:                            # noqa: BLE001
        pass
    names |= _windows_profiles()
    return {n for n in names if n and len(n) >= 3 and n not in {"root", "user"}}


def _windows_profiles() -> set[str]:
    """WSL から見える Windows のユーザープロファイル名（/mnt/c/Users/<名前>）。

    S006 で Windows 側の LM Studio を調べたとき、パスの外（「プロファイル名 X は読めない」などの文）にも
    プロファイル名が出た。パスの規則だけでは消えないので、名前そのものを伏せ字にする。
    """
    builtin = {"public", "default", "default user", "all users", "defaultuser0", "wsiaccount"}
    try:
        profiles = {d.name for d in Path("/mnt/c/Users").iterdir() if d.is_dir() and d.name.lower() not in builtin}
    except OSError:
        return set()
    # 「姓 名」のような名前は、語に分かれて現れることもある（コマンドの引数など）。4 文字以上の語も消す。
    parts = {w for n in profiles for w in re.split(r"[\s._-]+", n) if len(w) >= 4}
    return profiles | parts


# 順番に意味がある。具体的なもの（トークン・パス）から先に潰す。
REDACTIONS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"ghp_[A-Za-z0-9]{36}"), "<redacted>"),
    (re.compile(r"github_pat_[A-Za-z0-9_]{20,}"), "<redacted>"),
    (re.compile(r"\bsk-[A-Za-z0-9_\-]{20,}"), "<redacted>"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "<redacted>"),
    (re.compile(r"\bxox[abprs]-[A-Za-z0-9\-]{10,}"), "<redacted>"),
    (re.compile(r"(?i)\b(api[_-]?key|secret|token|password|passwd)\b(\s*[:=]\s*['\"]?)([^\s'\"]{8,})"),
     r"\1\2<redacted>"),
    (re.compile(r"[A-Za-z0-9._%+\-*]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"), "<email>"),
    (re.compile(r"/mnt/[a-z]/Users/[^/\s\"'`]+", re.I), "~"),
    (re.compile(r"[A-Za-z]:[\\/]+Users[\\/]+[^\\/\s\"'`]+", re.I), "~"),
    (re.compile(r"/home/[^/\s\"'`]+"), "~"),
    # LAN と Tailscale（100.64.0.0/10）のアドレス。10.x は WSL の DNS（10.255.255.254）など説明に使うので残す。
    (re.compile(r"\b(?:192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b"), "<private-ip>"),
    (re.compile(r"\b100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.\d{1,3}\.\d{1,3}\b"), "<private-ip>"),
    (re.compile(r"/Users/[^/\s\"'`]+"), "~"),
]


def redact(text: str) -> str:
    for pat, rep in REDACTIONS:
        text = pat.sub(rep, text)
    for name in _local_names():                  # slug（-home-<user>-...）や tmp パスに残る分
        text = re.sub(re.escape(name), "<user>", text)
    return text


def leftovers(text: str) -> list[str]:
    """伏せ字の取りこぼし。--check で使う。"""
    found = []
    for pat, _ in REDACTIONS:
        found += [m.group(0) for m in pat.finditer(text) if "<redacted>" not in m.group(0)]
    for name in _local_names():
        if name in text:
            found.append(name)
    return found


# --------------------------------------------------------------------------- 入力

def project_slug(path: Path) -> str:
    """Claude Code のプロジェクトディレクトリ名。英数字以外を "-" に潰したもの。"""
    return re.sub(r"[^A-Za-z0-9]", "-", str(path))


def find_transcript(hook: dict) -> Path | None:
    """フックの JSON（または手動実行の引数）から transcript の実体を突き止める。

    `transcript_path` が来ないフックイベントもあるので、その場合は
    session_id をファイル名に持つ jsonl を探す。worktree から手動で実行したときは
    ROOT が worktree になるので、CLAUDE_PROJECT_DIR（メインのチェックアウト）を優先する。
    """
    p = hook.get("transcript_path")
    if p and Path(p).exists():
        return Path(p)

    sid = hook.get("session_id")
    if not sid:
        return None
    projects = Path.home() / ".claude" / "projects"
    bases = [Path(os.environ["CLAUDE_PROJECT_DIR"])] if os.environ.get("CLAUDE_PROJECT_DIR") else []
    bases.append(ROOT)
    for base in bases:
        cand = projects / project_slug(base) / f"{sid}.jsonl"
        if cand.exists():
            return cand
    hits = sorted(projects.glob(f"*/{sid}.jsonl"))
    return hits[0] if hits else None


def latest_transcript(match: str | None = None) -> Path | None:
    """このプロジェクトで最後に更新された transcript（finish-session が今のセッションを指すのに使う）。

    同じプロジェクトで別のセッションが並行して動いていることがあるので、
    match（例: ブランチ名 feature/sNNN-<topic>）を渡すと、それを含む transcript に絞る。
    """
    base = Path(os.environ.get("CLAUDE_PROJECT_DIR") or ROOT)
    files = sorted((Path.home() / ".claude" / "projects" / project_slug(base)).glob("*.jsonl"),
                   key=lambda p: p.stat().st_mtime, reverse=True)
    for f in files:
        if match is None or match in f.read_text(encoding="utf-8", errors="replace"):
            return f
    return None


def read_records(path: Path) -> list[dict]:
    out = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except json.JSONDecodeError:
                continue                      # 書き込み途中の行は捨てる
    return out


# --------------------------------------------------------------------------- 整形

def blocks(message: dict) -> list:
    content = message.get("content")
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    return content if isinstance(content, list) else []


def clip(s: str, n: int) -> str:
    s = s.rstrip()
    return s if len(s) <= n else s[:n] + f"\n… （残り {len(s) - n:,} 字は生ログを参照）"


def render_user(rec: dict) -> list[str]:
    lines = []
    for b in blocks(rec.get("message") or {}):
        if b.get("type") == "text":
            lines.append(b["text"].strip())
        elif b.get("type") == "tool_result":
            body = b.get("content")
            if isinstance(body, list):
                body = "".join(x.get("text", "") for x in body if isinstance(x, dict))
            lines.append("<details><summary>ツール結果</summary>\n\n```\n"
                         + clip(str(body or ""), MAX_RESULT_CHARS) + "\n```\n\n</details>")
    return [x for x in lines if x]


def render_assistant(rec: dict) -> list[str]:
    lines = []
    for b in blocks(rec.get("message") or {}):
        kind = b.get("type")
        if kind == "text":
            lines.append(b["text"].strip())
        elif kind == "thinking":
            lines.append("<details><summary>思考</summary>\n\n"
                         + clip(b.get("thinking", ""), MAX_RESULT_CHARS) + "\n\n</details>")
        elif kind == "tool_use":
            arg = b.get("input") or {}
            label = (arg.get("description") or arg.get("command")
                     or arg.get("file_path") or arg.get("pattern") or "")
            head = f"**🔧 {b.get('name', '?')}**" + (f" — {str(label).splitlines()[0]}"
                                                    if label else "")
            lines.append(head + "\n\n<details><summary>入力</summary>\n\n```json\n"
                         + clip(json.dumps(arg, ensure_ascii=False, indent=1),
                                MAX_TOOL_INPUT_CHARS) + "\n```\n\n</details>")
    return [x for x in lines if x]


def stamp(rec: dict) -> str:
    ts = rec.get("timestamp") or ""
    return ts.replace("T", " ")[:19] if ts else ""


def render(records: list[dict], session_id: str) -> str:
    meta = next((r for r in records if r.get("cwd")), {})
    times = [r["timestamp"] for r in records if r.get("timestamp")]

    out = [f"# セッション記録 {session_id}", "",
           "| | |", "| --- | --- |",
           f"| 開始 | {times[0].replace('T', ' ')[:19] if times else '-'} |",
           f"| 最終更新 | {times[-1].replace('T', ' ')[:19] if times else '-'} |",
           f"| ブランチ | `{meta.get('gitBranch', '-')}` |",
           f"| 作業ディレクトリ | `{meta.get('cwd', '-')}` |",
           f"| やり取り | {sum(1 for r in records if r.get('type') in ('user', 'assistant'))} 件 |",
           "",
           "> 読むための整形版。ツール結果と思考は先頭だけを抜いてある。",
           "> メールアドレス・ローカルのユーザー名とパス・トークンらしき文字列は伏せ字にしてある。",
           "> 完全な生ログは作業者の手元の `log/local/raw/` にだけある（コミットしない）。", ""]

    for rec in records:
        kind = rec.get("type")
        if kind == "user":
            body = render_user(rec)
            head = "## 👤 ユーザー"
        elif kind == "assistant":
            body = render_assistant(rec)
            head = "## 🤖 Claude"
        else:
            continue
        if not body:
            continue
        when = stamp(rec)
        out.append(f"{head}{f'　`{when}`' if when else ''}")
        out.append("")
        out += ["\n".join(body), ""]

    return redact("\n".join(out) + "\n")


# --------------------------------------------------------------------------- 実行

def save(hook: dict, out_dir: Path) -> Path | None:
    src = find_transcript(hook)
    if src is None:
        return None

    session_id = hook.get("session_id") or src.stem
    records = read_records(src)
    day = (next((r["timestamp"] for r in records if r.get("timestamp")),
                datetime.now().isoformat()))[:10]
    name = f"{day}-{session_id}"

    raw = out_dir / "raw"
    raw.mkdir(parents=True, exist_ok=True)

    md = out_dir / f"{name}.md"
    md.write_text(render(records, session_id), encoding="utf-8")
    with src.open("rb") as f_in, gzip.open(raw / f"{name}.jsonl.gz", "wb", 6) as f_out:
        shutil.copyfileobj(f_in, f_out)
    return md


def check(paths: list[str]) -> int:
    bad = 0
    for p in paths:
        hits = leftovers(Path(p).read_text(encoding="utf-8"))
        if hits:
            bad += 1
            print(f"{p}: 伏せ字の取りこぼし {len(hits)} 件 例: {sorted(set(hits))[:5]}")
    print(f"検査 {len(paths)} 件 / 取りこぼしのあるファイル {bad} 件")
    return 1 if bad else 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--session", help="セッションID（手動実行用。標準入力を読まない）")
    ap.add_argument("--transcript", help="transcript の jsonl のパス（手動実行用）")
    ap.add_argument("--latest", action="store_true",
                    help="このプロジェクトで最後に更新された transcript を使う（手動実行用）")
    ap.add_argument("--match", help="--latest の候補を、この文字列を含む transcript に絞る（例: ブランチ名）")
    ap.add_argument("--out", default=str(DEFAULT_OUT), help="出力先（既定は log/local）")
    ap.add_argument("--check", nargs="+", metavar="MD", help="伏せ字の取りこぼしを検査する")
    args = ap.parse_args(argv)

    if args.check:
        return check(args.check)

    manual = bool(args.session or args.transcript or args.latest)
    if args.latest:
        t = latest_transcript(args.match)
        hook = {"session_id": t.stem if t else None, "transcript_path": str(t) if t else None}
    elif manual:
        hook = {"session_id": args.session, "transcript_path": args.transcript}
    else:
        try:
            hook = json.loads(sys.stdin.read() or "{}")
        except json.JSONDecodeError:
            hook = {}

    md = save(hook, Path(args.out))
    if manual:
        if md is None:
            print("transcript が見つからない", file=sys.stderr)
            return 1
        print(md)
    return 0


if __name__ == "__main__":
    is_check = "--check" in sys.argv[1:]
    try:
        sys.exit(main(sys.argv[1:]))
    except SystemExit:
        raise
    except Exception:                            # noqa: BLE001 — ログ取りで作業を止めない
        sys.exit(1 if is_check else 0)
