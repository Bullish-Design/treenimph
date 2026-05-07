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
