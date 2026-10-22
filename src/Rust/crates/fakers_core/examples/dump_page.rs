//! 新しいページの状態を 16 進で 1 行出す。相互運用ゲート（yrs → yjs）の入力。
//!   cargo run -q -p fakers_core --example dump_page [title]
fn main() {
    let title = std::env::args()
        .nth(1)
        .unwrap_or_else(|| "Interop".to_string());
    let state = fakers_core::new_page(&title, "h1", "p1");
    println!("{}", fakers_core::to_hex(&state));
}
