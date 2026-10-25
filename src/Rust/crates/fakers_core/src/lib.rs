//! Fakers Notion のコア。ブロック文書を yrs（Yjs の Rust 移植）の上に置く。
//!
//! 文書の状態は「update v1 のバイト列」として呼び出し側（Elixir の `DocumentServer`）が持ち、
//! この crate の関数はすべて純関数（decode → 操作 → encode）。状態を crate の中に持たない。
//! 理由は ADR-0003（NIF をホットスワップの対象にしない）。
//!
//! モデル: 根の `Y.Array("blocks")` に `Y.Map{ "id": string, "type": string, "text": Y.Text, "checked"?: bool, "indent"?: int }` を並べる。
//! `type` の値は fakers_shared の `BlockKind`。`checked` と `indent` は無ければ false と 0。
//! 文字位置は UTF-16 で数える（yjs の規則。`OffsetKind::Utf16`）。

pub mod formula;

use serde_json::{Map as JsonMap, Value};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::{
    Any, Array, ArrayRef, Doc, GetString, Map, MapPrelim, OffsetKind, Options, Out, ReadTxn,
    StateVector, Text, TextPrelim, TextRef, Transact, Update,
};

/// 根の配列の名前。クライアント（yjs）も同じ名前で開く。
pub const ROOT: &str = "blocks";

/// ブロックの種類（`type` キーの値）。
pub const KIND_PARAGRAPH: &str = "paragraph";
pub const KIND_HEADING: &str = "heading";

#[derive(Debug, thiserror::Error)]
pub enum CoreError {
    #[error("update を decode できない: {0}")]
    Decode(String),
    #[error("update を適用できない: {0}")]
    Apply(String),
    #[error("ブロックが無い: {0}")]
    NoSuchBlock(String),
    #[error("ブロックの形が違う: {0}")]
    Shape(String),
}

fn new_doc() -> Doc {
    let opts = Options {
        offset_kind: OffsetKind::Utf16,
        ..Options::default()
    };
    Doc::with_options(opts)
}

/// 状態（update v1）から Doc を組み立てる。空のバイト列は空の文書。
fn load(state: &[u8]) -> Result<Doc, CoreError> {
    let doc = new_doc();
    if !state.is_empty() {
        let update = Update::decode_v1(state).map_err(|e| CoreError::Decode(e.to_string()))?;
        let mut txn = doc.transact_mut();
        txn.apply_update(update)
            .map_err(|e| CoreError::Apply(e.to_string()))?;
    }
    Ok(doc)
}

/// Doc の全状態を update v1 で書き出す。
fn encode_full(doc: &Doc) -> Vec<u8> {
    doc.transact()
        .encode_state_as_update_v1(&StateVector::default())
}

/// 新しいページの初期状態。サーバがシードするので、クライアントが最初のブロック作成で競合しない。
/// 見出し（title の文字）と空の段落の 2 ブロック。
pub fn new_page(title: &str, heading_id: &str, para_id: &str) -> Vec<u8> {
    let doc = new_doc();
    let blocks = doc.get_or_insert_array(ROOT);
    {
        let mut txn = doc.transact_mut();
        push_block(&blocks, &mut txn, heading_id, KIND_HEADING, title);
        push_block(&blocks, &mut txn, para_id, KIND_PARAGRAPH, "");
    }
    encode_full(&doc)
}

fn push_block(
    blocks: &ArrayRef,
    txn: &mut yrs::TransactionMut<'_>,
    id: &str,
    kind: &str,
    text: &str,
) {
    let map = blocks.push_back(txn, MapPrelim::default());
    map.insert(txn, "id", id);
    map.insert(txn, "type", kind);
    map.insert(txn, "text", TextPrelim::new(text));
}

/// 状態に update を適用し、新しい全状態を返す。
pub fn apply_update(state: &[u8], update: &[u8]) -> Result<Vec<u8>, CoreError> {
    let doc = load(state)?;
    {
        let update = Update::decode_v1(update).map_err(|e| CoreError::Decode(e.to_string()))?;
        let mut txn = doc.transact_mut();
        txn.apply_update(update)
            .map_err(|e| CoreError::Apply(e.to_string()))?;
    }
    Ok(encode_full(&doc))
}

/// 状態の state vector（v1）。再接続時の差分計算に使う。
pub fn state_vector(state: &[u8]) -> Result<Vec<u8>, CoreError> {
    let doc = load(state)?;
    let sv = doc.transact().state_vector();
    Ok(sv.encode_v1())
}

/// `sv`（state vector v1）を持つ相手に送る差分 update。
pub fn diff(state: &[u8], sv: &[u8]) -> Result<Vec<u8>, CoreError> {
    let doc = load(state)?;
    let sv = StateVector::decode_v1(sv).map_err(|e| CoreError::Decode(e.to_string()))?;
    Ok(doc.transact().encode_state_as_update_v1(&sv))
}

/// ブロックの一覧を JSON（`[{"id","type","text","checked","indent"}]`）で。クライアントの FFI と同じ形。
pub fn blocks_json(state: &[u8]) -> Result<String, CoreError> {
    let doc = load(state)?;
    let blocks = doc.get_or_insert_array(ROOT);
    let txn = doc.transact();
    let mut out = Vec::new();
    for item in blocks.iter(&txn) {
        let Out::YMap(map) = item else {
            return Err(CoreError::Shape("blocks の要素が Y.Map ではない".into()));
        };
        let mut obj = JsonMap::new();
        obj.insert("id".into(), Value::String(string_field(&txn, &map, "id")?));
        obj.insert(
            "type".into(),
            Value::String(string_field(&txn, &map, "type")?),
        );
        let text = match map.get(&txn, "text") {
            Some(Out::YText(t)) => t.get_string(&txn),
            Some(Out::Any(Any::String(s))) => s.to_string(),
            _ => return Err(CoreError::Shape("text が Y.Text ではない".into())),
        };
        obj.insert("text".into(), Value::String(text));
        let checked = matches!(map.get(&txn, "checked"), Some(Out::Any(Any::Bool(true))));
        obj.insert("checked".into(), Value::Bool(checked));
        // 整数でないものと負の値は 0
        let indent = match map.get(&txn, "indent") {
            Some(Out::Any(Any::Number(n))) => n.as_i64().unwrap_or(0).max(0),
            _ => 0,
        };
        obj.insert("indent".into(), Value::from(indent));
        out.push(Value::Object(obj));
    }
    Ok(Value::Array(out).to_string())
}

fn string_field<T: ReadTxn>(txn: &T, map: &yrs::MapRef, key: &str) -> Result<String, CoreError> {
    match map.get(txn, key) {
        Some(Out::Any(Any::String(s))) => Ok(s.to_string()),
        _ => Err(CoreError::Shape(format!("{key} が文字列ではない"))),
    }
}

/// `block_id` のブロックの文字列の `utf16_index` に `insert` を差し込む。
/// 返り値は (新しい全状態, この編集だけの update)。テストと、サーバ側のシードに使う。
pub fn edit_text(
    state: &[u8],
    block_id: &str,
    utf16_index: u32,
    insert: &str,
) -> Result<(Vec<u8>, Vec<u8>), CoreError> {
    let doc = load(state)?;
    let blocks = doc.get_or_insert_array(ROOT);
    let before = doc.transact().state_vector();
    {
        let mut txn = doc.transact_mut();
        let text = find_text(&txn, &blocks, block_id)?;
        text.insert(&mut txn, utf16_index, insert);
    }
    let update = doc.transact().encode_state_as_update_v1(&before);
    Ok((encode_full(&doc), update))
}

fn find_text<T: ReadTxn>(txn: &T, blocks: &ArrayRef, block_id: &str) -> Result<TextRef, CoreError> {
    for item in blocks.iter(txn) {
        if let Out::YMap(map) = item
            && string_field(txn, &map, "id").ok().as_deref() == Some(block_id)
        {
            return match map.get(txn, "text") {
                Some(Out::YText(t)) => Ok(t),
                _ => Err(CoreError::Shape("text が Y.Text ではない".into())),
            };
        }
    }
    Err(CoreError::NoSuchBlock(block_id.to_string()))
}

/// 16 進の文字列にする（例題とテストで使う。`cargo run --example dump_page`）。
pub fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// 16 進の文字列を戻す。
pub fn from_hex(s: &str) -> Result<Vec<u8>, CoreError> {
    let s = s.trim();
    if !s.len().is_multiple_of(2) {
        return Err(CoreError::Decode("16 進の長さが奇数".into()));
    }
    (0..s.len())
        .step_by(2)
        .map(|i| {
            u8::from_str_radix(&s[i..i + 2], 16)
                .map_err(|e| CoreError::Decode(format!("16 進ではない: {e}")))
        })
        .collect()
}
