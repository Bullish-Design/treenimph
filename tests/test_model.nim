import std/options
import std/strutils
import unittest

import treenimph/model

suite "Expression Constructors":
  test "Ref basic":
    let e = Ref("identifier")
    check e.kind == ekRef
    check e.refName == "identifier"

  test "Text basic":
    let e = Text("=")
    check e.kind == ekText
    check e.textValue == "="

  test "Regex basic":
    let e = Regex("[a-z]+")
    check e.kind == ekRegex
    check e.regexPattern == "[a-z]+"

  test "Blank basic":
    let e = Blank()
    check e.kind == ekBlank

  test "Sequence varargs":
    let e = Sequence(Text("a"), Text("b"), Text("c"))
    check e.kind == ekSequence
    check e.items.len == 3

  test "Choice varargs":
    let e = Choice(Text("a"), Text("b"))
    check e.kind == ekChoice
    check e.items.len == 2

  test "Field basic":
    let e = Field("name", Ref("identifier"))
    check e.kind == ekField
    check e.fieldName == "name"
    check e.fieldExpr.kind == ekRef

  test "Alias default named":
    let e = Alias("name", Ref("identifier"))
    check e.kind == ekAlias
    check e.aliasNamed

  test "Alias unnamed":
    let e = Alias("name", Ref("identifier"), named = false)
    check not e.aliasNamed

  test "Precedence helpers":
    check PrecLeft(1, Ref("x")).precAssoc == assocLeft
    check PrecRight(2, Ref("x")).precAssoc == assocRight
    check PrecDynamic(3, Ref("x")).precAssoc == assocDynamic

suite "Rule and Grammar Constructors":
  test "underscore forces hidden":
    let r = mkRule("_expr", Blank(), hidden = false)
    check r.hidden

  test "canonical name prepends underscore when hidden":
    let r = mkRule("expr", Blank(), hidden = true)
    check r.canonicalName == "_expr"

  test "Grammar constructor captures options":
    let q = QueryFiles(highlights: some("h"), tags: none(string), locals: none(string), injections: none(string))
    let g = mkGrammar(
      name = "demo",
      rules = [mkRule("source", Blank())],
      word = some("source"),
      extras = [Regex("\\s+")],
      conflicts = [@["a", "b"]],
      supertypes = ["source"],
      inline = ["source"],
      externals = [Ref("ext")],
      queryFiles = some(q),
      scannerPath = some("src/scanner.c"),
    )
    check g.name == "demo"
    check g.rules.len == 1
    check g.word.get == "source"
    check g.extras.len == 1
    check g.conflicts.len == 1
    check g.supertypes.len == 1
    check g.inline.len == 1
    check g.externals.len == 1
    check g.queryFiles.isSome
    check g.scannerPath.isSome

  test "ExportConfig defaults":
    let cfg = mkExportConfig("out")
    check cfg.outDir == "out"
    check cfg.runGenerate == false
    check cfg.writeQueryStubs == true
    check cfg.overwrite == true

suite "Accessors":
  test "inner on wrapper":
    let e = Optional(Text("x"))
    check e.inner.kind == ekText

  test "inner on leaf raises":
    expect FieldDefect:
      discard Text("x").inner

  test "children on leaf":
    check Ref("x").children.len == 0

  test "children on sequence":
    let e = Sequence(Text("a"), Text("b"))
    check e.children.len == 2

suite "Summary":
  test "summary includes grammar and rules":
    let g = mkGrammar(
      name = "demo",
      rules = [
        mkRule("source", Blank()),
        mkRule("expr", Ref("source"), hidden = true),
      ]
    )
    let s = g.summary
    check s.contains("Grammar: demo (2 rules)")
    check s.contains("  source")
    check s.contains("  _expr")

suite "Expr stringify":
  test "leaf nodes":
    check $Ref("x") == "Ref(\"x\")"
    check $Text("hi") == "Text(\"hi\")"
    check $Regex("[0-9]+") == "Regex(\"[0-9]+\")"
    check $Blank() == "Blank()"

  test "wrapper nodes":
    check $Optional(Text("x")) == "Optional(Text(\"x\"))"
    check $ZeroOrMore(Ref("a")) == "ZeroOrMore(Ref(\"a\"))"

  test "compound nodes":
    let e = Sequence(Text("a"), Ref("b"))
    check $e == "Sequence(Text(\"a\"), Ref(\"b\"))"

  test "nil expression":
    let e: Expr = nil
    check $e == "<nil>"
