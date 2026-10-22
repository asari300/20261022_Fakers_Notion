//! 同時編集の収束、不正な update、UTF-16 の位置。

use fakers_core::{apply_update, blocks_json, diff, edit_text, new_page, state_vector};
use serde_json::Value;

fn texts(state: &[u8]) -> Vec<(String, String, String)> {
    let v: Value = serde_json::from_str(&blocks_json(state).unwrap()).unwrap();
    v.as_array()
        .unwrap()
        .iter()
        .map(|b| {
            (
                b["id"].as_str().unwrap().to_string(),
                b["type"].as_str().unwrap().to_string(),
                b["text"].as_str().unwrap().to_string(),
            )
        })
        .collect()
}

#[test]
fn new_page_has_heading_and_empty_paragraph() {
    let state = new_page("My page", "h1", "p1");
    assert_eq!(
        texts(&state),
        vec![
            ("h1".into(), "heading".into(), "My page".into()),
            ("p1".into(), "paragraph".into(), "".into()),
        ]
    );
}

#[test]
fn concurrent_edits_converge() {
    let base = new_page("T", "h1", "p1");
    // 2 つのクライアントが同じ状態から、同じ段落の先頭に同時に挿入する（client ID は Doc ごとに乱数）
    let (_, ua) = edit_text(&base, "p1", 0, "Hello ").unwrap();
    let (_, ub) = edit_text(&base, "p1", 0, "World").unwrap();

    let s1 = apply_update(&apply_update(&base, &ua).unwrap(), &ub).unwrap();
    let s2 = apply_update(&apply_update(&base, &ub).unwrap(), &ua).unwrap();

    assert_eq!(blocks_json(&s1).unwrap(), blocks_json(&s2).unwrap());
    let para = &texts(&s1)[1].2;
    assert!(
        para.contains("Hello ") && para.contains("World"),
        "{para:?}"
    );
    assert_eq!(para.len(), "Hello World".len());
}

#[test]
fn update_is_idempotent_and_reorderable() {
    let base = new_page("T", "h1", "p1");
    let (s_a, ua) = edit_text(&base, "p1", 0, "a").unwrap();
    let (_, ub) = edit_text(&s_a, "p1", 1, "b").unwrap();
    let once = apply_update(&apply_update(&base, &ua).unwrap(), &ub).unwrap();
    let twice = apply_update(&once, &ua).unwrap();
    assert_eq!(blocks_json(&once).unwrap(), blocks_json(&twice).unwrap());
    assert_eq!(texts(&twice)[1].2, "ab");
}

#[test]
fn invalid_update_is_error() {
    let base = new_page("T", "h1", "p1");
    assert!(apply_update(&base, &[0xff, 0xff, 0xff, 0xff]).is_err());
    assert!(fakers_core::from_hex("zz").is_err());
}

#[test]
fn unknown_block_is_error() {
    let base = new_page("T", "h1", "p1");
    assert!(edit_text(&base, "nope", 0, "x").is_err());
}

#[test]
fn utf16_positions_after_emoji() {
    // "😀" は UTF-16 で 2 単位、UTF-8 で 4 バイト。UTF-16 の 2 の位置に差し込めること。
    let base = new_page("T", "h1", "p1");
    let (s, _) = edit_text(&base, "p1", 0, "😀").unwrap();
    let (s, _) = edit_text(&s, "p1", 2, "x").unwrap();
    assert_eq!(texts(&s)[1].2, "😀x");
    let (s, _) = edit_text(&s, "p1", 1, "").unwrap();
    assert_eq!(texts(&s)[1].2, "😀x");
}

#[test]
fn diff_from_state_vector_brings_peer_up_to_date() {
    let base = new_page("T", "h1", "p1");
    let sv = state_vector(&base).unwrap();
    let (edited, _) = edit_text(&base, "p1", 0, "late").unwrap();
    let d = diff(&edited, &sv).unwrap();
    assert!(!d.is_empty());
    let caught_up = apply_update(&base, &d).unwrap();
    assert_eq!(
        blocks_json(&caught_up).unwrap(),
        blocks_json(&edited).unwrap()
    );
    // 追いついた相手への差分は空（state vector が同じ）
    let sv2 = state_vector(&caught_up).unwrap();
    let d2 = diff(&edited, &sv2).unwrap();
    assert_eq!(
        apply_update(&caught_up, &d2).unwrap().len(),
        caught_up.len()
    );
}
