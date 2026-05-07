import std/[options, strutils]
import unittest

import treenimph/diagnostics
import treenimph/[model, validate]

proc hasDiag(diags: seq[Diagnostic], needle: string): bool =
  for d in diags:
    if d.message.contains(needle):
      return true
  false

suite "Validate grammar-level":
  test "empty grammar name":
    let g = mkGrammar("", rules = [mkRule("source", Blank())])
    let diags = g.validate()
    check hasDiag(diags, "Grammar name must not be empty")

  test "no rules":
    let g = mkGrammar("demo", rules = [])
    let diags = g.validate()
    check hasDiag(diags, "must define at least one rule")

suite "Validate rule-level":
  test "duplicate canonical names":
    let g = mkGrammar("demo", rules = [
      mkRule("expr", Blank()),
      mkRule("expr", Blank()),
    ])
    let diags = g.validate()
    check hasDiag(diags, "Duplicate rule name")

  test "reserved prefix":
    let g = mkGrammar("demo", rules = [mkRule("MISSING_x", Blank())])
    let diags = g.validate()
    check hasDiag(diags, "reserved prefix")

suite "Validate expression refs":
  test "undefined ref":
    let g = mkGrammar("demo", rules = [mkRule("source", Ref("sourc"))])
    let diags = g.validate()
    check hasDiag(diags, "Unknown rule reference")

  test "invalid field name":
    let g = mkGrammar("demo", rules = [
      mkRule("source", Field("bad-name", Text("x"))),
    ])
    let diags = g.validate()
    check hasDiag(diags, "Invalid field name")

  test "empty alias name":
    let g = mkGrammar("demo", rules = [
      mkRule("source", Alias("", Text("x"))),
    ])
    let diags = g.validate()
    check hasDiag(diags, "Alias name must not be empty")

  test "empty sequence":
    let g = mkGrammar("demo", rules = [mkRule("source", Sequence())])
    let diags = g.validate()
    check hasDiag(diags, "Sequence must contain at least one item")

  test "empty choice":
    let g = mkGrammar("demo", rules = [mkRule("source", Choice())])
    let diags = g.validate()
    check hasDiag(diags, "Choice must contain at least one item")

suite "Validate config":
  test "invalid word":
    let g = mkGrammar(
      "demo",
      rules = [mkRule("source", Blank())],
      word = some("sourc"),
    )
    let diags = g.validate()
    check hasDiag(diags, "Word rule \"sourc\" does not exist")

  test "invalid extras ref":
    let g = mkGrammar(
      "demo",
      rules = [mkRule("source", Blank())],
      extras = [Ref("missing")],
    )
    let diags = g.validate()
    check hasDiag(diags, "Extras reference")

  test "bad conflict entry":
    let g = mkGrammar(
      "demo",
      rules = [mkRule("a", Blank()), mkRule("b", Blank())],
      conflicts = [@["a"]],
    )
    let diags = g.validate()
    check hasDiag(diags, "Conflict entry must contain at least 2")

  test "scanner path missing":
    let g = mkGrammar(
      "demo",
      rules = [mkRule("source", Blank())],
      scannerPath = some("/tmp/definitely-missing-scanner.c"),
    )
    let diags = g.validate()
    check hasDiag(diags, "does not exist")

suite "validateOrRaise":
  test "raises on errors":
    let g = mkGrammar("demo", rules = [mkRule("source", Ref("missing"))])
    expect ValidationError:
      g.validateOrRaise()

  test "does not raise on valid grammar":
    let g = mkGrammar("demo", rules = [mkRule("source", Blank())])
    g.validateOrRaise()
