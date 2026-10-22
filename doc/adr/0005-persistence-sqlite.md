# ADR-0005 永続化は SQLite（ecto_sqlite3）から始める

- 状態: **Accepted**（2026-10-22、S001。ユーザーの選択）。

## 背景

- この RPi には Postgres が入っていない。Docker は動いている。sqlite3 の CLI も無い。
- P1〜P4 は 1 ノード。複数ノードで共有する DB が要るのは P5（分散）から。
- RAM の空きが 1 GB 未満のことがあり、常駐するサービスは少ない方がよい。

## 決定

- **Ecto のアダプタは ecto_sqlite3（~> 0.26）。** `mix phx.new --database sqlite3`。外部サービス無しで動く。
- 文書は `documents` テーブルの 1 行（`id :binary_id`、`title :string`、`state :binary`、timestamps）。`state` は yjs の update v1 のバイト列（[ADR-0003](0003-crdt-yjs-yrs.md)）。
- 書き込みは `DocumentServer` が 1000 ms の debounce でまとめる（[architecture.md](../architecture.md#3-データの流れp1-の縦スライス)）。
- Postgres への移行は P5（複数ノード）で行う。Ecto のスキーマとクエリは移行できる範囲に留める（SQLite 固有の機能を使わない）。

## 結果

- exqlite は cc_precompiler で aarch64-linux-gnu のプリビルドを取る見込み。無ければ gcc で SQLite をビルドする（数分、約 400 MB RAM）。S002 で確かめる。
- DB の中身は sqlite3 の CLI が無いので `mix run -e 'IO.inspect Fakers.Repo.all(Fakers.Documents.Document)'` で見る。
- テストでは `Ecto.Adapters.SQL.Sandbox` の `{:shared, self()}` と、`DocumentServer` の debounce タイマーの相性に注意する（S002）。
