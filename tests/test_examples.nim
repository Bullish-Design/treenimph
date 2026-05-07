import unittest

import treenimph

suite "examples integration":
  test "arithmetic-like grammar validates and renders":
    let g = mkGrammar(
      "arithmetic",
      rules = [
        mkRule("expression", Choice(Ref("number"), Ref("binary_expression"))),
        mkRule("binary_expression", PrecLeft(1, Sequence(Ref("expression"), Text("+"), Ref("expression")))),
        mkRule("number", Regex("[0-9]+")),
      ],
    )
    g.validateOrRaise()
    check g.renderGrammarJs().len > 0

  test "json-like grammar validates":
    let g = mkGrammar(
      "json",
      rules = [
        mkRule("document", Ref("_value")),
        mkRule("_value", Choice(Ref("string"), Ref("number"))),
        mkRule("string", Regex("\"[^\"]*\"")),
        mkRule("number", Regex("[0-9]+")),
      ],
      extras = [Regex("\\s+")],
    )
    g.validateOrRaise()

  test "simple lang grammar validates":
    let g = mkGrammar(
      "simple_lang",
      rules = [
        mkRule("source_file", ZeroOrMore(Ref("statement"))),
        mkRule("statement", Ref("expression")),
        mkRule("expression", Choice(Ref("identifier"), Ref("number"))),
        mkRule("identifier", Regex("[a-zA-Z_][a-zA-Z0-9_]*")),
        mkRule("number", Regex("[0-9]+")),
      ],
    )
    g.validateOrRaise()
