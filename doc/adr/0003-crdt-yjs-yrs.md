# ADR-0003 CRDT はクライアント yjs・サーバ yrs。状態は BEAM 側のバイナリ、NIF は純関数

- 状態: **Proposed**（2026-10-22、S001）。S002 の相互運用ゲート（yrs の状態を yjs に適用できる）と 2 タブの同期が通ったら Accepted にする。

## 背景

- 共同編集には CRDT が要る。ブラウザとサーバの両方で同じワイヤ形式を扱う必要がある。
- 候補: yjs（JS）と yrs（Rust の移植。同じ lib0 v1 の形式）、Automerge、Loro。Elixir には yrs のバインディング y_ex（0.7〜0.8 系）もある。
- Rustler 0.38 は erl_nif の `upgrade` コールバックを `NULL` にする。OTP の文書では `upgrade` が `NULL` のライブラリは、古い版が読み込まれたままだと新しい版を読み込めない（[research/stack.md](../research/stack.md)）。
- 調査で分かった互換性の落とし穴（出典は research/stack.md）:
  - yrs 0.28 の client ID は既定で 53 bit。yjs 13.6.x と話すには feature `small-client` が要る。
  - yrs の文字位置は既定で UTF-8 のバイト。yjs は UTF-16。`Options::offset_kind` を `Utf16` にする。

## 決定

1. **クライアントは yjs 13.6.33（npm）、サーバは yrs 0.28（`features = ["small-client"]`）。** 同じ update v1 のバイト列を Phoenix Channel のバイナリ payload で運ぶ。
2. **すべての `Doc` を `OffsetKind::Utf16` で作る。** JS 側の差分計算も UTF-16 の位置で行う。
3. **文書の状態は `DocumentServer` が update v1 のバイナリとして持つ。NIF は `apply_update(state, update) -> new_state` のような純関数にし、`ResourceArc` を持たない。**
   - 理由 1（ホットスワップ）: 状態がバイナリなら NIF のライブラリに縛られない。`DocumentServer` と Channel は自由に差し替えられ、`Fakers.Native` は滅多に変えない安定ファサードになる。
   - 理由 2（単純さ）: 純関数はテストしやすく、永続化はバイト列をそのまま書くだけ。
   - 理由 3（性能）: 毎回 decode → apply → encode で O(文書サイズ)。P1 の規模（KB）では十分速い見込み。足りなくなったらバイナリと並べて `ResourceArc<Mutex<Doc>>` をキャッシュし、アップグレード後にバイナリから作り直す。
4. **サーバは、クライアントが送った update のバイト列をマージが成功した後にそのまま他へ配る。** 全員が CRDT なので重複と順序の入れ替わりは無害。
5. **再接続**: `sync` を受けるたびに `Y.encodeStateVectorFromUpdate(state)` から差分を作って push する。
6. 自前の Rustler crate（`fakers_nif`）を書く。y_ex は使わない（コアを Rust 側に持つ方針。y_ex は候補として残す）。
7. Rust コアを WASM にしてクライアントでも使う案（b）は P5 に回す。RPi での二重ビルド、`ywasm` 相当の約 1.2 MB の束、Lustre の起動が非同期になる費用が、P1 では見合わない。wasm32 ターゲットは入っているので後で足せる。

## 結果

- S002 の手順 3 を**相互運用ゲート**にする: `cargo run -p fakers_core --example dump_page | node test/interop.mjs`。失敗したら UI に進まない。
- 既知の制限: P1 の各ブロックは controlled input なので、入力中のブロックにリモート編集が来るとキャレットが末尾に飛ぶ（P2 で contenteditable にする）。
- 見出しブロックの文字と `documents.title` 列は P1 では同期しない（P2）。
