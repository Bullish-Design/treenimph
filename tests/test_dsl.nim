import std/[options, strutils]
import std/macros
import std/sets
import unittest

import treenimph/model
import treenimph/validate
import treenimph/render_js
import treenimph/helpers
import treenimph/runner
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
        let rhs = def[2]
        let transformedRhs = transformExpr(rhs, letBound)
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


suite "DSL — bare identifiers become Ref":
  test "single identifier rule body":
    let g = testGrammar "test":
      source = other
      other = re"[a-z]+"
    check g.rules[0].body.kind == ekRef
    check g.rules[0].body.refName == "other"

  test "identifier reference":
    let g = testGrammar "test":
      source = hidden_rule
      hidden_rule = re"[a-z]+"
    check g.rules[0].body.kind == ekRef
    check g.rules[0].body.refName == "hidden_rule"

suite "DSL — string literals become Text":
  test "string literal in sequence":
    let g = testGrammar "test":
      source = ["hello", "world"]
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items[0].kind == ekText
    check g.rules[0].body.items[0].textValue == "hello"
    check g.rules[0].body.items[1].kind == ekText
    check g.rules[0].body.items[1].textValue == "world"

  test "string literal as sole rule body":
    let g = testGrammar "test":
      source = "keyword"
    check g.rules[0].body.kind == ekText
    check g.rules[0].body.textValue == "keyword"

suite "DSL — re\"\" becomes Regex":
  test "regex rule":
    let g = testGrammar "test":
      source = re"[0-9]+"
    check g.rules[0].body.kind == ekRegex
    check g.rules[0].body.regexPattern == "[0-9]+"

suite "DSL — brackets become Sequence":
  test "multi-element bracket":
    let g = testGrammar "test":
      source = ["a", "b", "c"]
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items.len == 3

  test "single-element bracket unwraps":
    let g = testGrammar "test":
      source = [re"[a-z]+"]
    check g.rules[0].body.kind == ekRegex

  test "bracket with mixed types":
    let g = testGrammar "test":
      source = ["let", identifier, "=", expression]
      identifier = re"[a-z]+"
      expression = re"[0-9]+"
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items[0].kind == ekText
    check g.rules[0].body.items[1].kind == ekRef
    check g.rules[0].body.items[2].kind == ekText
    check g.rules[0].body.items[3].kind == ekRef

suite "DSL — | becomes Choice":
  test "two-way choice":
    let g = testGrammar "test":
      source = alpha | beta
      alpha = "a"
      beta = "b"
    check g.rules[0].body.kind == ekChoice
    check g.rules[0].body.items.len == 2

  test "three-way choice is flattened":
    let g = testGrammar "test":
      source = alpha | beta | gamma
      alpha = "a"
      beta = "b"
      gamma = "c"
    check g.rules[0].body.kind == ekChoice
    check g.rules[0].body.items.len == 3

  test "choice of sequences":
    let g = testGrammar "test":
      source = ["a", "b"] | ["c", "d"]
    check g.rules[0].body.kind == ekChoice
    check g.rules[0].body.items.len == 2
    check g.rules[0].body.items[0].kind == ekSequence
    check g.rules[0].body.items[1].kind == ekSequence

suite "DSL — prefix operators":
  test "? becomes Optional":
    let g = testGrammar "test":
      source = ?other
      other = "x"
    check g.rules[0].body.kind == ekOptional
    check g.rules[0].body.item.kind == ekRef

  test "* becomes ZeroOrMore":
    let g = testGrammar "test":
      source = *other
      other = "x"
    check g.rules[0].body.kind == ekZeroOrMore
    check g.rules[0].body.item.kind == ekRef

  test "+ becomes OneOrMore":
    let g = testGrammar "test":
      source = +other
      other = "x"
    check g.rules[0].body.kind == ekOneOrMore
    check g.rules[0].body.item.kind == ekRef

suite "DSL — @ becomes Field":
  test "field with identifier ref":
    let g = testGrammar "test":
      source = name@identifier
      identifier = re"[a-z]+"
    check g.rules[0].body.kind == ekField
    check g.rules[0].body.fieldName == "name"
    check g.rules[0].body.fieldExpr.kind == ekRef
    check g.rules[0].body.fieldExpr.refName == "identifier"

  test "field with complex expression":
    let g = testGrammar "test":
      source = op@("+" | "-")
    check g.rules[0].body.kind == ekField
    check g.rules[0].body.fieldName == "op"
    check g.rules[0].body.fieldExpr.kind == ekChoice

  test "field in sequence":
    let g = testGrammar "test":
      source = ["let", name@identifier, "=", value@expression, ";"]
      identifier = re"[a-z]+"
      expression = re"[0-9]+"
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items[1].kind == ekField
    check g.rules[0].body.items[1].fieldName == "name"
    check g.rules[0].body.items[3].kind == ekField
    check g.rules[0].body.items[3].fieldName == "value"

suite "DSL — precedence":
  test "prec_left":
    let g = testGrammar "test":
      source = prec_left(1, [left@source, "+", right@source])
    check g.rules[0].body.kind == ekPrecedence
    check g.rules[0].body.precLevel == 1
    check g.rules[0].body.precAssoc == assocLeft
    check g.rules[0].body.precExpr.kind == ekSequence

  test "prec_right":
    let g = testGrammar "test":
      source = prec_right(2, [source, "**", source])
    check g.rules[0].body.kind == ekPrecedence
    check g.rules[0].body.precAssoc == assocRight
    check g.rules[0].body.precLevel == 2

  test "prec_dynamic":
    let g = testGrammar "test":
      source = prec_dynamic(3, identifier)
      identifier = re"[a-z]+"
    check g.rules[0].body.kind == ekPrecedence
    check g.rules[0].body.precAssoc == assocDynamic

  test "prec (no assoc)":
    let g = testGrammar "test":
      source = prec(1, identifier)
      identifier = re"[a-z]+"
    check g.rules[0].body.kind == ekPrecedence
    check g.rules[0].body.precAssoc == assocNone

suite "DSL — token and immediate_token":
  test "token wraps expression":
    let g = testGrammar "test":
      source = token("+" | "-")
    check g.rules[0].body.kind == ekToken
    check g.rules[0].body.tokenExpr.kind == ekChoice

  test "immediate_token wraps expression":
    let g = testGrammar "test":
      source = immediate_token(re"\\s+")
    check g.rules[0].body.kind == ekImmediateToken

suite "DSL — alias":
  test "alias basic":
    let g = testGrammar "test":
      source = alias("other_name", identifier)
      identifier = re"[a-z]+"
    check g.rules[0].body.kind == ekAlias
    check g.rules[0].body.aliasName == "other_name"
    check g.rules[0].body.aliasNamed == true

  test "alias named=false":
    let g = testGrammar "test":
      source = alias("lit", identifier, named = false)
      identifier = re"[a-z]+"
    check g.rules[0].body.kind == ekAlias
    check g.rules[0].body.aliasNamed == false

suite "DSL — let bindings":
  test "let-bound variable is not converted to Ref":
    let g = testGrammar "test":
      let myExpr = identifier
      source = myExpr
      identifier = re"[a-z]+"
    check g.rules[0].body.kind == ekRef
    check g.rules[0].body.refName == "identifier"

  test "let-bound string becomes Text":
    let g = testGrammar "test":
      let sep = ","
      source = [identifier, sep, identifier]
      identifier = re"[a-z]+"
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items[1].kind == ekText
    check g.rules[0].body.items[1].textValue == ","

  test "non-let-bound identifier becomes Ref":
    let g = testGrammar "test":
      source = identifier
      identifier = re"[a-z]+"
    check g.rules[0].body.kind == ekRef
    check g.rules[0].body.refName == "identifier"

suite "DSL — helper passthrough":
  test "delimitedList with transformed args":
    let g = testGrammar "test":
      source = delimitedList(item, ",")
      item = re"[a-z]+"
    check g.rules[0].body.kind == ekSequence

  test "delimitedList with trailing":
    let g = testGrammar "test":
      source = delimitedList(item, ",", trailing = true)
      item = re"[a-z]+"
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items.len == 3

  test "balanced with transformed args":
    let g = testGrammar "test":
      source = balanced("(", ")", expr)
      expr = re"[a-z]+"
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items[0].kind == ekText
    check g.rules[0].body.items[0].textValue == "("

suite "DSL — grammar config":
  test "extras":
    let g = testGrammar "test":
      extras = [re"\\s+"]
      source = "x"
    check g.extras.len == 1
    check g.extras[0].kind == ekRegex

  test "word":
    let g = testGrammar "test":
      word = identifier
      source = identifier
      identifier = re"[a-z]+"
    check g.word.isSome
    check g.word.get == "identifier"

  test "supertypes":
    let g = testGrammar "test":
      supertypes = [expression_node]
      source = expression_node
      expression_node = "x"
    check g.supertypes.len == 1
    check g.supertypes[0] == "expression_node"

  test "inline":
    let g = testGrammar "test":
      inline = [helper_rule]
      source = helper_rule
      helper_rule = "x"
    check g.inline.len == 1
    check g.inline[0] == "helper_rule"

  test "conflicts":
    let g = testGrammar "test":
      conflicts = [[source, other]]
      source = other
      other = "x"
    check g.conflicts.len == 1
    check g.conflicts[0] == @["source", "other"]

  test "externals":
    let g = testGrammar "test":
      externals = [ext_token]
      source = "x"
    check g.externals.len == 1
    check g.externals[0].kind == ekRef

  test "scannerPath":
    let g = testGrammar "test":
      scannerPath = "/tmp/scanner.c"
      source = "x"
    check g.scannerPath.isSome
    check g.scannerPath.get == "/tmp/scanner.c"

suite "DSL — validates correctly":
  test "DSL grammar passes validation":
    let g = testGrammar "test":
      source = *statement
      statement = let_stmt | expr_stmt
      let_stmt = ["let", name@identifier, "=", value@expression, ";"]
      expr_stmt = [expression, ";"]
      expression = identifier | number
      identifier = re"[a-zA-Z_][a-zA-Z0-9_]*"
      number = re"[0-9]+"
    g.validateOrRaise()

  test "DSL grammar with extras validates":
    let g = testGrammar "test":
      extras = [re"\\s+"]
      source = "hello"
    g.validateOrRaise()
