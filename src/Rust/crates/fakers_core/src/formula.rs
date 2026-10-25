//! フォーミュラ言語（Notion の formula 2.0 の部分集合）。字句解析 → 構文解析 → 型検査 → 評価。
//!
//! `compile` でプロパティの型（schema）に対して型検査まで済ませ、`Formula::eval` で行ごとに評価する。
//! 型は 数値・テキスト・真偽値 の 3 つ。日付・リスト・メソッド記法（`x.length()`）はまだ無い。
//! エラーの `pos` は式の先頭からの文字数（Unicode のスカラー値で数える）。

use std::collections::HashMap;
use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Type {
    Number,
    Text,
    Bool,
}

impl fmt::Display for Type {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            Type::Number => "数値",
            Type::Text => "テキスト",
            Type::Bool => "真偽値",
        })
    }
}

#[derive(Debug, Clone, PartialEq)]
pub enum Value {
    Number(f64),
    Text(String),
    Bool(bool),
}

impl Value {
    pub fn ty(&self) -> Type {
        match self {
            Value::Number(_) => Type::Number,
            Value::Text(_) => Type::Text,
            Value::Bool(_) => Type::Bool,
        }
    }

    /// 空の値。行に値が無いプロパティはこれとして読む。`empty()` はこれと等しいかを返す。
    pub fn empty(ty: Type) -> Value {
        match ty {
            Type::Number => Value::Number(0.0),
            Type::Text => Value::Text(String::new()),
            Type::Bool => Value::Bool(false),
        }
    }
}

impl fmt::Display for Value {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Value::Number(n) => write!(f, "{n}"),
            Value::Text(s) => f.write_str(s),
            Value::Bool(b) => write!(f, "{b}"),
        }
    }
}

#[derive(Debug, Clone, PartialEq, thiserror::Error)]
#[error("{msg}（位置 {pos}）")]
pub struct FormulaError {
    pub pos: usize,
    pub msg: String,
}

fn err<T>(pos: usize, msg: impl Into<String>) -> Result<T, FormulaError> {
    Err(FormulaError {
        pos,
        msg: msg.into(),
    })
}

// ---- 字句解析 ----

#[derive(Debug, Clone, PartialEq)]
enum Tok {
    Num(f64),
    Str(String),
    Bool(bool),
    Ident(String),
    /// 演算子。`and` / `&&`、`or` / `||`、`not` / `!` はそれぞれ前者に揃える。
    Op(&'static str),
    LParen,
    RParen,
    Comma,
    Eof,
}

struct Token {
    tok: Tok,
    pos: usize,
}

const OPS: [&str; 17] = [
    "==", "!=", "<=", ">=", "&&", "||", "+", "-", "*", "/", "%", "^", "<", ">", "!", "?", ":",
];

fn lex(src: &str) -> Result<Vec<Token>, FormulaError> {
    let cs: Vec<char> = src.chars().collect();
    let mut out = Vec::new();
    let mut i = 0;
    while i < cs.len() {
        let pos = i;
        let c = cs[i];
        let tok = if c.is_whitespace() {
            i += 1;
            continue;
        } else if c.is_ascii_digit()
            || (c == '.' && cs.get(i + 1).is_some_and(char::is_ascii_digit))
        {
            while i < cs.len() && (cs[i].is_ascii_digit() || cs[i] == '.') {
                i += 1;
            }
            let s: String = cs[pos..i].iter().collect();
            match s.parse() {
                Ok(n) => Tok::Num(n),
                Err(_) => return err(pos, format!("数値として読めない: {s}")),
            }
        } else if c == '"' {
            i += 1;
            let mut s = String::new();
            loop {
                match cs.get(i) {
                    None => return err(pos, "文字列が閉じていない"),
                    Some('"') => break,
                    Some('\\') => {
                        s.push(match cs.get(i + 1) {
                            Some('"') => '"',
                            Some('\\') => '\\',
                            Some('n') => '\n',
                            _ => return err(i, "知らないエスケープ"),
                        });
                        i += 1;
                    }
                    Some(&ch) => s.push(ch),
                }
                i += 1;
            }
            i += 1;
            Tok::Str(s)
        } else if c.is_alphabetic() || c == '_' {
            while i < cs.len() && (cs[i].is_alphanumeric() || cs[i] == '_') {
                i += 1;
            }
            match cs[pos..i].iter().collect::<String>().as_str() {
                "true" => Tok::Bool(true),
                "false" => Tok::Bool(false),
                "and" => Tok::Op("and"),
                "or" => Tok::Op("or"),
                "not" => Tok::Op("not"),
                s => Tok::Ident(s.to_string()),
            }
        } else if let Some(op) = OPS.iter().find(|op| {
            op.chars()
                .enumerate()
                .all(|(k, oc)| cs.get(i + k) == Some(&oc))
        }) {
            i += op.chars().count();
            Tok::Op(match *op {
                "&&" => "and",
                "||" => "or",
                "!" => "not",
                o => o,
            })
        } else {
            i += 1;
            match c {
                '(' => Tok::LParen,
                ')' => Tok::RParen,
                ',' => Tok::Comma,
                _ => return err(pos, format!("使えない文字: {c}")),
            }
        };
        out.push(Token { tok, pos });
    }
    out.push(Token {
        tok: Tok::Eof,
        pos: cs.len(),
    });
    Ok(out)
}

// ---- 構文解析（Pratt） ----

#[derive(Debug, Clone)]
enum Expr {
    Lit(Value),
    Prop(String),
    Unary(&'static str, Box<Node>),
    Binary(&'static str, Box<Node>, Box<Node>),
    /// `c ? a : b` と `if(c, a, b)`。
    If(Box<Node>, Box<Node>, Box<Node>),
    Call(String, Vec<Node>),
}

#[derive(Debug, Clone)]
struct Node {
    expr: Expr,
    pos: usize,
    /// 木の高さ。型検査と評価は再帰するので、深すぎる式を構文解析の時点で弾く。
    height: usize,
}

/// 入れ子の上限。NIF の dirty scheduler のスタックは小さい（既定 40 kword）。
const MAX_DEPTH: usize = 100;

fn node(expr: Expr, pos: usize) -> Result<Node, FormulaError> {
    let kids: Vec<&Node> = match &expr {
        Expr::Lit(_) | Expr::Prop(_) => vec![],
        Expr::Unary(_, a) => vec![a],
        Expr::Binary(_, a, b) => vec![a, b],
        Expr::If(c, a, b) => vec![c, a, b],
        Expr::Call(_, args) => args.iter().collect(),
    };
    let height = 1 + kids.iter().map(|k| k.height).max().unwrap_or(0);
    if height > MAX_DEPTH {
        return err(pos, format!("式の入れ子が深すぎる（上限 {MAX_DEPTH}）"));
    }
    Ok(Node { expr, pos, height })
}

/// 中置演算子の結合力（左, 右）。右の方が大きければ左結合。
fn infix_bp(op: &str) -> Option<(u8, u8)> {
    Some(match op {
        "?" => (2, 1),
        "or" => (3, 4),
        "and" => (5, 6),
        "==" | "!=" | "<" | "<=" | ">" | ">=" => (9, 10),
        "+" | "-" => (11, 12),
        "*" | "/" | "%" => (13, 14),
        "^" => (18, 17),
        _ => return None,
    })
}
const NOT_BP: u8 = 7;
const NEG_BP: u8 = 15;

struct Parser {
    toks: Vec<Token>,
    i: usize,
    /// `expr` の再帰の深さ。括弧だけの入れ子は木の高さに表れないので別に数える。
    depth: usize,
}

impl Parser {
    fn peek(&self) -> &Token {
        &self.toks[self.i]
    }

    fn next(&mut self) -> &Token {
        let t = &self.toks[self.i];
        if t.tok != Tok::Eof {
            self.i += 1;
        }
        t
    }

    fn expect(&mut self, want: Tok, what: &str) -> Result<(), FormulaError> {
        let t = self.next();
        if t.tok == want {
            Ok(())
        } else {
            err(t.pos, format!("{what} が必要"))
        }
    }

    fn expr(&mut self, min_bp: u8) -> Result<Node, FormulaError> {
        self.depth += 1;
        if self.depth > MAX_DEPTH {
            return err(
                self.peek().pos,
                format!("式の入れ子が深すぎる（上限 {MAX_DEPTH}）"),
            );
        }
        let r = self.expr_inner(min_bp);
        self.depth -= 1;
        r
    }

    fn expr_inner(&mut self, min_bp: u8) -> Result<Node, FormulaError> {
        let mut lhs = self.prefix()?;
        while let Token {
            tok: Tok::Op(op),
            pos,
        } = self.peek()
        {
            let (op, pos) = (*op, *pos);
            let Some((lbp, rbp)) = infix_bp(op) else {
                break;
            };
            if lbp < min_bp {
                break;
            }
            self.next();
            let rhs = self.expr(rbp)?;
            let expr = if op == "?" {
                self.expect(Tok::Op(":"), ":")?;
                let other = self.expr(rbp)?;
                Expr::If(Box::new(lhs), Box::new(rhs), Box::new(other))
            } else {
                Expr::Binary(op, Box::new(lhs), Box::new(rhs))
            };
            lhs = node(expr, pos)?;
        }
        Ok(lhs)
    }

    fn prefix(&mut self) -> Result<Node, FormulaError> {
        let Token { tok, pos } = self.next();
        let (tok, pos) = (tok.clone(), *pos);
        let expr = match tok {
            Tok::Num(n) => Expr::Lit(Value::Number(n)),
            Tok::Str(s) => Expr::Lit(Value::Text(s)),
            Tok::Bool(b) => Expr::Lit(Value::Bool(b)),
            Tok::Op("-") => Expr::Unary("-", Box::new(self.expr(NEG_BP)?)),
            Tok::Op("not") => Expr::Unary("not", Box::new(self.expr(NOT_BP)?)),
            Tok::LParen => {
                let inner = self.expr(0)?;
                self.expect(Tok::RParen, ")")?;
                return Ok(inner);
            }
            Tok::Ident(name) => {
                self.expect(Tok::LParen, "(")?;
                let mut args = Vec::new();
                if self.peek().tok == Tok::RParen {
                    self.next();
                } else {
                    loop {
                        args.push(self.expr(0)?);
                        let t = self.next();
                        match t.tok {
                            Tok::Comma => {}
                            Tok::RParen => break,
                            _ => return err(t.pos, ", か ) が必要"),
                        }
                    }
                }
                call(name, args, pos)?
            }
            Tok::Eof => return err(pos, "式が途中で終わっている"),
            _ => return err(pos, "ここに式が必要"),
        };
        node(expr, pos)
    }
}

/// `prop` と `if` は関数の形で書くが、構文として扱う。
fn call(name: String, mut args: Vec<Node>, pos: usize) -> Result<Expr, FormulaError> {
    match name.as_str() {
        "prop" => match args.as_slice() {
            [
                Node {
                    expr: Expr::Lit(Value::Text(p)),
                    ..
                },
            ] => Ok(Expr::Prop(p.clone())),
            _ => err(pos, "prop の引数はプロパティ名の文字列 1 つ"),
        },
        "if" if args.len() == 3 => {
            let (b, a, c) = (args.pop(), args.pop(), args.pop());
            let bx = |n: Option<Node>| Box::new(n.expect("引数は 3 つ"));
            Ok(Expr::If(bx(c), bx(a), bx(b)))
        }
        "if" => err(pos, "if の引数は 3 つ"),
        _ => Ok(Expr::Call(name, args)),
    }
}

// ---- 型検査 ----

fn check(n: &Node, schema: &HashMap<String, Type>) -> Result<Type, FormulaError> {
    use Type::*;
    let mismatch = |what: &str, tys: &[Type]| {
        let tys: Vec<String> = tys.iter().map(Type::to_string).collect();
        err(n.pos, format!("{what} に使えない型: {}", tys.join(", ")))
    };
    match &n.expr {
        Expr::Lit(v) => Ok(v.ty()),
        Expr::Prop(p) => match schema.get(p) {
            Some(t) => Ok(*t),
            None => err(n.pos, format!("プロパティが無い: {p}")),
        },
        Expr::Unary(op, a) => match (*op, check(a, schema)?) {
            ("-", Number) => Ok(Number),
            ("not", Bool) => Ok(Bool),
            (op, t) => mismatch(op, &[t]),
        },
        Expr::Binary(op, a, b) => match (*op, check(a, schema)?, check(b, schema)?) {
            ("+", Text, Text) => Ok(Text),
            ("+" | "-" | "*" | "/" | "%" | "^", Number, Number) => Ok(Number),
            ("<" | "<=" | ">" | ">=", Number, Number) | ("<" | "<=" | ">" | ">=", Text, Text) => {
                Ok(Bool)
            }
            ("==" | "!=", x, y) if x == y => Ok(Bool),
            ("and" | "or", Bool, Bool) => Ok(Bool),
            (op, x, y) => mismatch(op, &[x, y]),
        },
        Expr::If(c, a, b) => {
            let c = check(c, schema)?;
            if c != Bool {
                return err(n.pos, format!("条件は真偽値: {c}"));
            }
            let (x, y) = (check(a, schema)?, check(b, schema)?);
            if x != y {
                return err(n.pos, format!("2 つの分岐の型が違う: {x}, {y}"));
            }
            Ok(x)
        }
        Expr::Call(name, args) => {
            let tys = args
                .iter()
                .map(|a| check(a, schema))
                .collect::<Result<Vec<_>, _>>()?;
            match (name.as_str(), tys.as_slice()) {
                ("length" | "toNumber", [Text]) => Ok(Number),
                ("lower" | "upper", [Text]) => Ok(Text),
                ("contains", [Text, Text]) => Ok(Bool),
                ("format", [_]) => Ok(Text),
                ("empty", [_]) => Ok(Bool),
                ("round", [Number] | [Number, Number]) => Ok(Number),
                ("floor" | "ceil" | "abs" | "sqrt", [Number]) => Ok(Number),
                ("min" | "max", ts) if !ts.is_empty() && ts.iter().all(|t| *t == Number) => {
                    Ok(Number)
                }
                (f, ts) if FUNCS.contains(&f) => mismatch(f, ts),
                (f, _) => err(n.pos, format!("知らない関数: {f}")),
            }
        }
    }
}

const FUNCS: [&str; 14] = [
    "length", "toNumber", "lower", "upper", "contains", "format", "empty", "round", "floor",
    "ceil", "abs", "sqrt", "min", "max",
];

// ---- 評価 ----

/// 型検査を通したフォーミュラ。
#[derive(Debug, Clone)]
pub struct Formula {
    root: Node,
    ty: Type,
    schema: HashMap<String, Type>,
}

/// 字句解析・構文解析・型検査をする。`schema` はプロパティ名からその型。
pub fn compile(src: &str, schema: &HashMap<String, Type>) -> Result<Formula, FormulaError> {
    let mut p = Parser {
        toks: lex(src)?,
        i: 0,
        depth: 0,
    };
    let root = p.expr(0)?;
    if let Token { tok, pos } = p.peek()
        && *tok != Tok::Eof
    {
        return err(*pos, "式の後ろに余分なものがある");
    }
    let ty = check(&root, schema)?;
    Ok(Formula {
        root,
        ty,
        schema: schema.clone(),
    })
}

impl Formula {
    /// 結果の型。
    pub fn ty(&self) -> Type {
        self.ty
    }

    /// 1 行を評価する。行に無いプロパティは空の値（0・空文字・false）として読む。
    pub fn eval(&self, row: &HashMap<String, Value>) -> Result<Value, FormulaError> {
        self.eval_node(&self.root, row)
    }

    fn eval_node(&self, n: &Node, row: &HashMap<String, Value>) -> Result<Value, FormulaError> {
        use Value::*;
        let ev = |m: &Node| self.eval_node(m, row);
        let v = match &n.expr {
            Expr::Lit(v) => v.clone(),
            Expr::Prop(p) => {
                let ty = self.schema[p];
                match row.get(p) {
                    None => Value::empty(ty),
                    Some(v) if v.ty() == ty => v.clone(),
                    Some(v) => {
                        return err(n.pos, format!("{p} の値が {ty} でない: {}", v.ty()));
                    }
                }
            }
            Expr::Unary(op, a) => match (*op, ev(a)?) {
                ("-", Number(x)) => Number(-x),
                ("not", Bool(x)) => Bool(!x),
                _ => return internal(n.pos),
            },
            // and / or は右辺を必要なときだけ評価する。
            Expr::Binary("and", a, b) => match ev(a)? {
                Bool(false) => Bool(false),
                _ => ev(b)?,
            },
            Expr::Binary("or", a, b) => match ev(a)? {
                Bool(true) => Bool(true),
                _ => ev(b)?,
            },
            Expr::Binary(op, a, b) => match (*op, ev(a)?, ev(b)?) {
                ("+", Text(x), Text(y)) => Text(x + &y),
                ("+", Number(x), Number(y)) => Number(x + y),
                ("-", Number(x), Number(y)) => Number(x - y),
                ("*", Number(x), Number(y)) => Number(x * y),
                ("/", Number(x), Number(y)) => Number(x / y),
                ("%", Number(x), Number(y)) => Number(x % y),
                ("^", Number(x), Number(y)) => Number(x.powf(y)),
                ("==", x, y) => Bool(x == y),
                ("!=", x, y) => Bool(x != y),
                (op, Number(x), Number(y)) => Bool(cmp(op, x.partial_cmp(&y))),
                (op, Text(x), Text(y)) => Bool(cmp(op, Some(x.cmp(&y)))),
                _ => return internal(n.pos),
            },
            Expr::If(c, a, b) => match ev(c)? {
                Bool(true) => ev(a)?,
                _ => ev(b)?,
            },
            Expr::Call(name, args) => {
                let args = args.iter().map(ev).collect::<Result<Vec<_>, _>>()?;
                match (name.as_str(), args.as_slice()) {
                    ("length", [Text(s)]) => Number(s.chars().count() as f64),
                    ("toNumber", [Text(s)]) => match s.trim().parse() {
                        Ok(x) => Number(x),
                        Err(_) => return err(n.pos, format!("数値に変換できない: {s}")),
                    },
                    ("lower", [Text(s)]) => Text(s.to_lowercase()),
                    ("upper", [Text(s)]) => Text(s.to_uppercase()),
                    ("contains", [Text(s), Text(t)]) => Bool(s.contains(t.as_str())),
                    ("format", [v]) => Text(v.to_string()),
                    ("empty", [v]) => Bool(*v == Value::empty(v.ty())),
                    ("round", [Number(x)]) => Number(x.round()),
                    ("round", [Number(x), Number(d)]) => {
                        let k = 10f64.powf(d.trunc());
                        Number((x * k).round() / k)
                    }
                    ("floor", [Number(x)]) => Number(x.floor()),
                    ("ceil", [Number(x)]) => Number(x.ceil()),
                    ("abs", [Number(x)]) => Number(x.abs()),
                    ("sqrt", [Number(x)]) => Number(x.sqrt()),
                    ("min" | "max", xs) => {
                        let xs = xs.iter().filter_map(|v| match v {
                            Number(x) => Some(*x),
                            _ => None,
                        });
                        Number(if name == "min" {
                            xs.fold(f64::INFINITY, f64::min)
                        } else {
                            xs.fold(f64::NEG_INFINITY, f64::max)
                        })
                    }
                    _ => return internal(n.pos),
                }
            }
        };
        // 0 での割り算・負の数の平方根・桁あふれをここでまとめて弾く。
        match v {
            Number(x) if !x.is_finite() => err(n.pos, "計算の結果が数値にならない"),
            v => Ok(v),
        }
    }
}

fn cmp(op: &str, o: Option<std::cmp::Ordering>) -> bool {
    use std::cmp::Ordering::*;
    matches!(
        (op, o),
        ("<", Some(Less))
            | ("<=", Some(Less | Equal))
            | (">", Some(Greater))
            | (">=", Some(Greater | Equal))
    )
}

/// 型検査を通っていれば起きない。NIF から呼ぶので panic にしない。
fn internal<T>(pos: usize) -> Result<T, FormulaError> {
    err(pos, "内部エラー: 型検査と評価が食い違った")
}
