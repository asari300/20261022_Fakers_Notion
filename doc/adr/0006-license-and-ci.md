# ADR-0006 ライセンスは MIT OR Apache-2.0、CI は毎回全部を検査する

- 状態: **Accepted**（2026-10-22、S003。ライセンスはユーザーの決定）。

## 背景

- P1 の完了条件に「ライセンスを決める」「CI が main で通る」が残っていた。
- 兄弟リポジトリ GlobeMode は MIT OR Apache-2.0 で、差分だけを検査する CI を持つ（その ADR-0006）。

## 決定

- **ライセンスは MIT OR Apache-2.0。** `LICENSE-MIT` と `LICENSE-APACHE` を置き、`pyproject.toml`、Cargo workspace、`gleam.toml`、`package.json` に書く。寄稿も同じ条件で受け入れる。
- **CI は GitHub Actions の `.github/workflows/ci.yml`。** push to main、pull request、手動で動く。`test`（`mise run test` = Rust・相互運用・Gleam・Elixir・E2E）と `docs`（`mise run docs:check`）の 2 ジョブ。runner は x86_64 の ubuntu-24.04。ツールの版は `mise.toml` / `mise.lock`。
- 差分だけを検査する仕組みは入れない（shortcut）。遅くなったら GlobeMode の方式を移す。

## 結果

- CI の結果は作業記録に書く。Elixir の依存ライセンスの監査（`mix licenses` 相当）と `cargo deny` は未導入。
