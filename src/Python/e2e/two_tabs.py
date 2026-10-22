#!/usr/bin/env python3
"""2 タブの E2E 検査（P1 の完了条件。doc/roadmap.md）。

Phoenix を PORT=4100（E2E_PORT で変更可）で起動し、Playwright の Chromium で次を確かめる。
  1. タブ 1 でページを作る → URL が #/p/<id> になり、見出しと段落の 2 ブロックが出る
  2. タブ 2 で同じ URL を開く → 同じ 2 ブロックが出る
  3. タブ 1 の段落に入力 → タブ 2 に反映される（5 s 以内。実測の遅れを表示する）
  4. タブ 1 で Enter → 新しいブロックが両方に現れる。タブ 2 で入力、タブ 1 で種別を見出しに → 反映
  5. サーバを止めて起動し直し、両タブをリロード → 3 ブロックと内容が残っている

  uv run python src/Python/e2e/two_tabs.py        # mise run test:e2e（build:web の後）
サーバのログは log/local/e2e-server.log（git 管理外）。
"""

from __future__ import annotations

import os
import re
import signal
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

from playwright.sync_api import expect, sync_playwright

ROOT = Path(__file__).resolve().parents[3]
APP = ROOT / "src" / "Elixir" / "fakers"
PORT = int(os.environ.get("E2E_PORT", "4100"))
BASE = f"http://127.0.0.1:{PORT}"
LOG = ROOT / "log" / "local" / "e2e-server.log"


def mix(*args: str) -> None:
    subprocess.run(["mix", *args], cwd=APP, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)


def start_server() -> subprocess.Popen:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    log = LOG.open("a", encoding="utf-8")
    env = {**os.environ, "PORT": str(PORT), "MIX_ENV": "dev"}
    proc = subprocess.Popen(["mix", "phx.server"], cwd=APP, env=env, start_new_session=True, stdout=log, stderr=subprocess.STDOUT)
    deadline = time.time() + 300
    while time.time() < deadline:
        if proc.poll() is not None:
            raise SystemExit(f"サーバが先に終了した（終了コード {proc.returncode}）。{LOG} を見る")
        try:
            urllib.request.urlopen(f"{BASE}/api/pages", timeout=1)
            return proc
        except Exception:  # noqa: BLE001
            time.sleep(0.5)
    raise SystemExit("サーバが起動しない")


def stop_server(proc: subprocess.Popen) -> None:
    os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
    try:
        proc.wait(timeout=60)
    except subprocess.TimeoutExpired:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        proc.wait()


def main() -> int:
    mix("ecto.create", "--quiet")
    mix("ecto.migrate", "--quiet")
    proc = start_server()
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            ctx = browser.new_context()
            t1 = ctx.new_page()
            t1.goto(f"{BASE}/#/")
            title = f"E2E {time.strftime('%H:%M:%S')}"

            # 1. 作成
            t1.fill(".new-page-input", title)
            t1.locator(".new-page button").click()
            t1.wait_for_url(re.compile(r"#/p/[0-9a-f-]{36}$"), timeout=15_000)
            url = t1.url
            inputs1 = t1.locator(".block-input")
            expect(inputs1).to_have_count(2, timeout=15_000)
            expect(inputs1.nth(0)).to_have_value(title)
            expect(t1.locator(".status")).to_contain_text("joined", timeout=10_000)

            # 2. タブ 2 で同じ URL
            t2 = ctx.new_page()
            t2.goto(url)
            inputs2 = t2.locator(".block-input")
            expect(inputs2).to_have_count(2, timeout=15_000)
            expect(inputs2.nth(0)).to_have_value(title)

            # 3. タブ 1 → タブ 2
            para1 = inputs1.nth(1)
            para1.click()
            para1.press_sequentially("hello from tab 1")
            started = time.perf_counter()
            expect(inputs2.nth(1)).to_have_value("hello from tab 1", timeout=5_000)
            latency_ms = (time.perf_counter() - started) * 1000

            # 4. Enter で新しいブロック、タブ 2 で入力、タブ 1 で種別
            para1.press("End")
            para1.press("Enter")
            expect(inputs1).to_have_count(3, timeout=5_000)
            expect(inputs2).to_have_count(3, timeout=5_000)
            inputs2.nth(2).fill("from tab 2")
            expect(inputs1.nth(2)).to_have_value("from tab 2", timeout=5_000)
            t1.locator(".block-toggle").nth(2).click()
            expect(t2.locator(".block").nth(2)).to_have_class(re.compile(r"block-heading"), timeout=5_000)

            # 5. 再起動後も残る（debounce の flush を待ってから止める）
            time.sleep(1.5)
            stop_server(proc)
            proc = start_server()
            for t in (t1, t2):
                t.reload()
                ins = t.locator(".block-input")
                expect(ins).to_have_count(3, timeout=20_000)
                expect(ins.nth(0)).to_have_value(title)
                expect(ins.nth(1)).to_have_value("hello from tab 1")
                expect(ins.nth(2)).to_have_value("from tab 2")
                expect(t.locator(".block").nth(2)).to_have_class(re.compile(r"block-heading"))
                expect(t.locator(".status")).to_contain_text("joined", timeout=10_000)
            browser.close()
        print(f"OK e2e: {url} / tab1→tab2 {latency_ms:.0f} ms / 3 ブロックが再起動後も残った")
        return 0
    finally:
        stop_server(proc)


if __name__ == "__main__":
    sys.exit(main())
