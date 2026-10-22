//! `Fakers.Native`（Elixir）の NIF。すべて `DirtyCpu`（文書全体の decode が 1 ms を超えうるため）。
//! 状態は Elixir 側がバイナリで持ち、ここでは `fakers_core` の純関数を 1 対 1 で包むだけ（ADR-0003）。

use rustler::{Binary, Env, NewBinary};

fn to_binary<'a>(env: Env<'a>, bytes: &[u8]) -> Binary<'a> {
    let mut out = NewBinary::new(env, bytes.len());
    out.as_mut_slice().copy_from_slice(bytes);
    out.into()
}

#[rustler::nif(schedule = "DirtyCpu")]
fn new_page<'a>(env: Env<'a>, title: String, heading_id: String, para_id: String) -> Binary<'a> {
    to_binary(env, &fakers_core::new_page(&title, &heading_id, &para_id))
}

#[rustler::nif(schedule = "DirtyCpu")]
fn apply_update<'a>(
    env: Env<'a>,
    state: Binary<'a>,
    update: Binary<'a>,
) -> Result<Binary<'a>, String> {
    fakers_core::apply_update(state.as_slice(), update.as_slice())
        .map(|s| to_binary(env, &s))
        .map_err(|e| e.to_string())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn state_vector<'a>(env: Env<'a>, state: Binary<'a>) -> Result<Binary<'a>, String> {
    fakers_core::state_vector(state.as_slice())
        .map(|s| to_binary(env, &s))
        .map_err(|e| e.to_string())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn diff<'a>(env: Env<'a>, state: Binary<'a>, sv: Binary<'a>) -> Result<Binary<'a>, String> {
    fakers_core::diff(state.as_slice(), sv.as_slice())
        .map(|s| to_binary(env, &s))
        .map_err(|e| e.to_string())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn blocks_json(state: Binary<'_>) -> Result<String, String> {
    fakers_core::blocks_json(state.as_slice()).map_err(|e| e.to_string())
}

#[rustler::nif(schedule = "DirtyCpu")]
fn edit_text<'a>(
    env: Env<'a>,
    state: Binary<'a>,
    block_id: String,
    utf16_index: u32,
    insert: String,
) -> Result<(Binary<'a>, Binary<'a>), String> {
    fakers_core::edit_text(state.as_slice(), &block_id, utf16_index, &insert)
        .map(|(s, u)| (to_binary(env, &s), to_binary(env, &u)))
        .map_err(|e| e.to_string())
}

rustler::init!("Elixir.Fakers.Native");
