import std/[options, strutils]
import unittest

import treenimph/[model, render_js]

suite "render_js":
  test "renders simple grammar":
    let g = mkGrammar("demo", rules = [mkRule("source", Text("x"))])
    let output = g.renderGrammarJs()
    check output.contains("module.exports = grammar")
    check output.contains("source: $ => 'x'")

  test "renders precedence and wrappers":
    let g = mkGrammar("demo", rules = [
      mkRule("source", PrecLeft(1, Sequence(Ref("left"), Text("+"), Ref("right")))),
      mkRule("left", Text("a")),
      mkRule("right", Text("b")),
    ])
    let output = g.renderGrammarJs()
    check output.contains("prec.left(1")
    check output.contains("seq(")

  test "snapshot json-like grammar":
    let value = Ref("_value")
    let comma = Text(",")
    let g = mkGrammar(
      "json_like",
      rules = [
        mkRule("document", value),
        mkRule("_value", Choice(Ref("object"), Ref("array"), Ref("string"), Ref("number"), Ref("true"), Ref("false"), Ref("null"))),
        mkRule("object", Sequence(Text("{"), Optional(Sequence(Ref("pair"), ZeroOrMore(Sequence(comma, Ref("pair"))), Optional(comma))), Text("}"))),
        mkRule("pair", Sequence(Field("key", Ref("string")), Text(":"), Field("value", value))),
        mkRule("array", Sequence(Text("["), Optional(Sequence(value, ZeroOrMore(Sequence(comma, value)), Optional(comma))), Text("]"))),
        mkRule("string", Regex("\"[^\"]*\"")),
        mkRule("number", Regex("[0-9]+")),
        mkRule("true", Text("true")),
        mkRule("false", Text("false")),
        mkRule("null", Text("null")),
      ],
      extras = [Regex("\\s+")],
    )

    let output = g.renderGrammarJs()
    let expected = readFile("tests/snapshots/json_like_grammar.js")
    check output == expected

  test "raises on nil rule body":
    let g = Grammar(
      name: "broken",
      rules: @[Rule(name: "source", body: nil, hidden: false)],
    )
    expect AssertionDefect:
      discard g.renderGrammarJs()

suite "escapeJsSingleQuote":
  test "passes through normal text":
    check escapeJsSingleQuote("hello world") == "hello world"

  test "escapes backslash":
    check escapeJsSingleQuote("a\\b") == "a\\\\b"

  test "escapes single quote":
    check escapeJsSingleQuote("it's") == "it\\'s"

  test "escapes newline and carriage return":
    check escapeJsSingleQuote("a\nb\rc") == "a\\nb\\rc"

  test "escapes tab":
    check escapeJsSingleQuote("a\tb") == "a\\tb"

  test "escapes null byte":
    check escapeJsSingleQuote("a\0b") == "a\\0b"

  test "escapes control characters as hex":
    check escapeJsSingleQuote("\x01") == "\\x01"
    check escapeJsSingleQuote("\x1F") == "\\x1f"
    check escapeJsSingleQuote("\x0B") == "\\x0b"

  test "combined escaping":
    check escapeJsSingleQuote("it's\na \\test\0") == "it\\'s\\na \\\\test\\0"

suite "escapeRegexSlash":
  test "passes through normal pattern":
    check escapeRegexSlash("[a-z]+") == "[a-z]+"

  test "escapes forward slash":
    check escapeRegexSlash("a/b") == "a\\/b"

  test "preserves existing backslash escapes":
    check escapeRegexSlash("\\d+") == "\\d+"

  test "escapes slash but preserves backslash-slash":
    check escapeRegexSlash("a\\/b/c") == "a\\/b\\/c"
