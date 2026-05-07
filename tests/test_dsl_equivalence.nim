import std/strutils
import std/macros
import std/sets
import unittest

import treenimph/model
import treenimph/helpers
import treenimph/render_js
import treenimph/validate
import treenimph/dsl {.all.}

macro testGrammar*(name: string, body: untyped): untyped =
  expectKind body, nnkStmtList
  var letBound: HashSet[string]
  var letSections: seq[NimNode]
  var configArgs: seq[NimNode]
  var ruleExprs: seq[NimNode]
  for stmt in body:
    case stmt.kind
    of nnkLetSection:
      var newLetSection = newNimNode(nnkLetSection)
      for def in stmt:
        expectKind def, nnkIdentDefs
        let varName = def[0]
        if varName.kind != nnkIdent:
          error("let binding name must be a bare identifier", varName)
        letBound.incl varName.strVal
        let transformedRhs = transformExpr(def[2], letBound)
        var newDef = newNimNode(nnkIdentDefs)
        newDef.add varName
        newDef.add def[1]
        newDef.add transformedRhs
        newLetSection.add newDef
      letSections.add newLetSection
    of nnkAsgn:
      let lhs = stmt[0]
      let rhs = stmt[1]
      if lhs.kind != nnkIdent:
        error("Left-hand side must be a bare identifier", lhs)
      let lhsName = lhs.strVal
      if isReservedConfigName(lhsName):
        let configValue = transformConfigValue(lhsName, rhs, letBound)
        configArgs.add newNimNode(nnkExprEqExpr).add(ident(lhsName), configValue)
      else:
        let ruleBody = transformExpr(rhs, letBound)
        ruleExprs.add newCall(ident("mkRule"), newStrLitNode(lhsName), ruleBody)
    of nnkCommentStmt:
      discard
    else:
      error("Unexpected statement in grammar block", stmt)

  var rulesArray = newNimNode(nnkBracket)
  for r in ruleExprs:
    rulesArray.add r
  var grammarCall = newCall(ident("mkGrammar"), name)
  grammarCall.add newNimNode(nnkExprEqExpr).add(ident("rules"), rulesArray)
  for arg in configArgs:
    grammarCall.add arg
  result = newStmtList()
  for letSec in letSections:
    result.add letSec
  result.add grammarCall


suite "DSL equivalence — simple_lang":
  test "DSL and raw API produce identical grammar.js":
    let rawGrammar = mkGrammar(
      "simple_lang",
      rules = [
        mkRule("source_file", ZeroOrMore(Ref("statement"))),
        mkRule("statement", Choice(Ref("let_stmt"), Ref("expr_stmt"))),
        mkRule("let_stmt", Sequence(Text("let"), Field("name", Ref("identifier")), Text("="), Field("value", Ref("expression")), Text(";"))),
        mkRule("expr_stmt", Sequence(Ref("expression"), Text(";"))),
        mkRule("expression", Choice(Ref("identifier"), Ref("number"))),
        mkRule("identifier", Regex("[a-zA-Z_][a-zA-Z0-9_]*")),
        mkRule("number", Regex("[0-9]+")),
      ],
    )
    rawGrammar.validateOrRaise()

    let dslGrammar = testGrammar "simple_lang":
      source_file = *statement
      statement = let_stmt | expr_stmt
      let_stmt = ["let", name@identifier, "=", value@expression, ";"]
      expr_stmt = [expression, ";"]
      expression = identifier | number
      identifier = re"[a-zA-Z_][a-zA-Z0-9_]*"
      number = re"[0-9]+"
    dslGrammar.validateOrRaise()

    check rawGrammar.renderGrammarJs() == dslGrammar.renderGrammarJs()

suite "DSL equivalence — arithmetic":
  test "DSL and raw API produce identical grammar.js":
    let rawGrammar = mkGrammar(
      "arithmetic",
      rules = [
        mkRule("expression", Choice(Ref("number"), Ref("binary_expression"), Ref("parenthesized_expression"))),
        mkRule("binary_expression", PrecLeft(1, Sequence(
          Field("left", Ref("expression")),
          Field("operator", Choice(Text("+"), Text("-"), Text("*"), Text("/"))),
          Field("right", Ref("expression")),
        ))),
        mkRule("parenthesized_expression", balanced("(", ")", Ref("expression"))),
        mkRule("number", Regex("[0-9]+")),
      ],
    )
    rawGrammar.validateOrRaise()

    let dslGrammar = testGrammar "arithmetic":
      expression = number | binary_expression | parenthesized_expression
      binary_expression = prec_left(1, [left@expression, operator@("+" | "-" | "*" | "/"), right@expression])
      parenthesized_expression = balanced("(", ")", expression)
      number = re"[0-9]+"
    dslGrammar.validateOrRaise()

    check rawGrammar.renderGrammarJs() == dslGrammar.renderGrammarJs()

suite "DSL equivalence — json_like":
  test "DSL and raw API produce identical grammar.js":
    let rawValue = Ref("value_node")
    let rawComma = Text(",")
    let rawGrammarMatching = mkGrammar(
      "json",
      extras = [Regex("\\\\s+")],
      rules = [
        mkRule("document", rawValue),
        mkRule("value_node", Choice(Ref("json_object"), Ref("array"), Ref("string_rule"), Ref("number_rule"), Ref("true_lit"), Ref("false_lit"), Ref("null_lit"))),
        mkRule("json_object", Sequence(Text("{"), Optional(delimitedList(Ref("pair"), rawComma, trailing = true)), Text("}"))),
        mkRule("pair", Sequence(Field("key", Ref("string_rule")), Text(":"), Field("val", rawValue))),
        mkRule("array", Sequence(Text("["), Optional(delimitedList(rawValue, rawComma, trailing = true)), Text("]"))),
        mkRule("string_rule", Regex("[a-zA-Z_]+")),
        mkRule("number_rule", Regex("-?[0-9]+(\\\\.[0-9]+)?([eE][+-]?[0-9]+)?")),
        mkRule("true_lit", Text("true")),
        mkRule("false_lit", Text("false")),
        mkRule("null_lit", Text("null")),
      ],
    )

    let dslGrammar = testGrammar "json":
      extras = [re"\\s+"]

      let value = value_node
      let comma = ","

      document = value
      value_node = json_object | array | string_rule | number_rule | true_lit | false_lit | null_lit
      json_object = ["{", ?delimitedList(pair, comma, trailing = true), "}"]
      pair = [key@string_rule, ":", val@value]
      array = ["[", ?delimitedList(value, comma, trailing = true), "]"]
      string_rule = re"[a-zA-Z_]+"
      number_rule = re"-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?"
      true_lit = "true"
      false_lit = "false"
      null_lit = "null"
    dslGrammar.validateOrRaise()

    check rawGrammarMatching.renderGrammarJs() == dslGrammar.renderGrammarJs()
