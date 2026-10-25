//! フォーミュラの例題集。1 行が 1 題（式・期待する値 / 期待するエラーの位置と文言の一部）。

use std::collections::HashMap;

use fakers_core::formula::{Type, Value, compile};

fn schema() -> HashMap<String, Type> {
    [
        ("名前", Type::Text),
        ("価格", Type::Number),
        ("数量", Type::Number),
        ("済み", Type::Bool),
        ("メモ", Type::Text),
    ]
    .into_iter()
    .map(|(k, t)| (k.to_string(), t))
    .collect()
}

/// 「メモ」は行に無い（空として読む）。
fn row() -> HashMap<String, Value> {
    [
        ("名前", Value::Text("りんご🍎".into())),
        ("価格", Value::Number(120.0)),
        ("数量", Value::Number(3.0)),
        ("済み", Value::Bool(true)),
    ]
    .into_iter()
    .map(|(k, v)| (k.to_string(), v))
    .collect()
}

fn n(x: f64) -> Value {
    Value::Number(x)
}
fn t(s: &str) -> Value {
    Value::Text(s.into())
}
fn b(x: bool) -> Value {
    Value::Bool(x)
}

#[test]
fn examples() {
    let cases: &[(&str, Value)] = &[
        // 算術と優先順位
        ("1 + 2 * 3", n(7.0)),
        ("(1 + 2) * 3", n(9.0)),
        ("10 - 4 - 3", n(3.0)),
        ("2 ^ 3 ^ 2", n(512.0)),
        ("-2 ^ 2", n(-4.0)),
        ("7 % 3", n(1.0)),
        ("1 / 4", n(0.25)),
        (".5 + 1.5", n(2.0)),
        // プロパティ
        ("prop(\"価格\") * prop(\"数量\")", n(360.0)),
        ("prop(\"メモ\")", t("")),
        ("empty(prop(\"メモ\"))", b(true)),
        ("empty(prop(\"名前\"))", b(false)),
        ("empty(0)", b(true)),
        // テキスト
        ("\"a\" + \"b\"", t("ab")),
        ("length(prop(\"名前\"))", n(4.0)),
        ("upper(\"abc\")", t("ABC")),
        ("lower(\"ABC\")", t("abc")),
        ("contains(prop(\"名前\"), \"りん\")", b(true)),
        ("format(prop(\"価格\")) + \"円\"", t("120円")),
        ("format(0.5)", t("0.5")),
        ("format(true)", t("true")),
        ("toNumber(\" 42 \") + 1", n(43.0)),
        ("\"say \\\"hi\\\"\\n\"", t("say \"hi\"\n")),
        // 比較と論理
        ("prop(\"価格\") >= 100", b(true)),
        ("\"abc\" < \"abd\"", b(true)),
        ("1 == 1 and \"x\" != \"y\"", b(true)),
        ("true && false || true", b(true)),
        ("not prop(\"済み\")", b(false)),
        ("!false", b(true)),
        ("not 1 == 2", b(true)),
        ("false and 1 / 0 > 0", b(false)),
        ("true or 1 / 0 > 0", b(true)),
        // 条件
        ("if(prop(\"済み\"), \"✅\", \"…\")", t("✅")),
        (
            "prop(\"数量\") > 5 ? \"多い\" : prop(\"数量\") > 1 ? \"ふつう\" : \"少ない\"",
            t("ふつう"),
        ),
        // 数値の関数
        ("round(2.5)", n(3.0)),
        ("round(2.71828, 2)", n(2.72)),
        ("floor(-1.5)", n(-2.0)),
        ("ceil(1.2)", n(2.0)),
        ("abs(-3)", n(3.0)),
        ("sqrt(16)", n(4.0)),
        ("min(3, 1, 2)", n(1.0)),
        ("max(prop(\"価格\"), 200)", n(200.0)),
    ];
    let (schema, row) = (schema(), row());
    for (src, want) in cases {
        let f = compile(src, &schema).unwrap_or_else(|e| panic!("{src}: {e}"));
        assert_eq!(f.ty(), want.ty(), "{src}");
        assert_eq!(
            &f.eval(&row).unwrap_or_else(|e| panic!("{src}: {e}")),
            want,
            "{src}"
        );
    }
}

#[test]
fn compile_errors() {
    // (式, 位置, 文言の一部)
    let cases: &[(&str, usize, &str)] = &[
        ("1 +", 3, "途中で終わっている"),
        ("(1 + 2", 6, ")"),
        ("1 2", 2, "余分"),
        ("\"abc", 0, "閉じていない"),
        ("1.2.3", 0, "数値として読めない"),
        ("1 # 2", 2, "使えない文字"),
        ("prop(\"無い\")", 0, "プロパティが無い"),
        ("prop(1)", 0, "prop の引数"),
        ("1 + \"a\"", 2, "+ に使えない型: 数値, テキスト"),
        ("-\"a\"", 0, "- に使えない型"),
        ("if(1, 2, 3)", 0, "条件は真偽値"),
        ("if(true, 1, \"a\")", 0, "分岐の型が違う"),
        ("if(true, 1)", 0, "if の引数は 3 つ"),
        ("true ? 1", 8, ":"),
        ("1 == \"1\"", 2, "== に使えない型"),
        ("1 < 2 < 3", 6, "< に使えない型: 真偽値, 数値"),
        ("length(1)", 0, "length に使えない型"),
        ("max()", 0, "max に使えない型"),
        ("foo(1)", 0, "知らない関数"),
        ("prop", 4, "("),
        ("min(1 2)", 6, ", か )"),
        ("\"a\\q\"", 2, "エスケープ"),
    ];
    let schema = schema();
    for (src, pos, msg) in cases {
        let e = compile(src, &schema).expect_err(src);
        assert_eq!(e.pos, *pos, "{src}: {e}");
        assert!(e.msg.contains(msg), "{src}: {e}");
    }
}

#[test]
fn runtime_errors() {
    let cases: &[(&str, &str)] = &[
        ("1 / 0", "数値にならない"),
        ("sqrt(-1)", "数値にならない"),
        ("10 ^ 400", "数値にならない"),
        ("toNumber(prop(\"名前\"))", "数値に変換できない"),
    ];
    let (schema, row) = (schema(), row());
    for (src, msg) in cases {
        let e = compile(src, &schema).unwrap().eval(&row).expect_err(src);
        assert!(e.msg.contains(msg), "{src}: {e}");
    }
}

#[test]
fn row_value_of_wrong_type_is_an_error() {
    let f = compile("prop(\"価格\") + 1", &schema()).unwrap();
    let row = HashMap::from([("価格".to_string(), t("高い"))]);
    let e = f.eval(&row).unwrap_err();
    assert!(e.msg.contains("価格 の値が 数値 でない"), "{e}");
}

#[test]
fn deep_nesting_is_rejected_not_overflowed() {
    let schema = schema();
    let parens = |k: usize| format!("{}1{}", "(".repeat(k), ")".repeat(k));
    let chain = |k: usize| format!("1{}", "+1".repeat(k));
    let nots = |k: usize| format!("{}true", "not ".repeat(k));
    for src in [parens(50), chain(50), nots(50)] {
        assert!(compile(&src, &schema).is_ok(), "{src}");
    }
    for src in [parens(100_000), chain(100_000), nots(100_000)] {
        let e = compile(&src, &schema).unwrap_err();
        assert!(e.msg.contains("深すぎる"), "{e}");
    }
}
