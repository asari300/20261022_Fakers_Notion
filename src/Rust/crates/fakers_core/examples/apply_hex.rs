//! 標準入力の 1 行目（状態の 16 進）に 2 行目（update の 16 進）を適用し、ブロックの JSON を出す。
//! 相互運用ゲート（yjs → yrs）の出口。
use std::io::Read;

fn main() {
    let mut input = String::new();
    std::io::stdin().read_to_string(&mut input).expect("stdin");
    let mut lines = input.lines();
    let state = fakers_core::from_hex(lines.next().unwrap_or("")).expect("state hex");
    let update = fakers_core::from_hex(lines.next().unwrap_or("")).expect("update hex");
    let new_state = fakers_core::apply_update(&state, &update).expect("apply");
    println!("{}", fakers_core::blocks_json(&new_state).expect("json"));
}
