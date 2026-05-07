# TreeNimph DSL Implementation Guide

**Date:** 2026-05-07
**Prerequisite reading:** `V2_MACRO_REFACTOR_CONCEPT.md`, `ROADMAP.md`
**Baseline commit:** `2bdbc53`

This document is a step-by-step implementation guide for the TreeNimph macro DSL. Each step includes the exact code to write, where to put it, and the tests that must pass before moving on.

---

## Table of Contents

1. [Step 1: Runner Module](#step-1-runner-module)
2. [Step 2: Wire Runner into Root Module](#step-2-wire-runner-into-root-module)
3. [Step 3: Update Examples to Use `run()`](#step-3-update-examples-to-use-run)
4. [Step 4: Runner Tests](#step-4-runner-tests)
5. [Step 5: DSL Module — Scaffold and Expression Transformer](#step-5-dsl-module--scaffold-and-expression-transformer)
6. [Step 6: DSL Module — Grammar Block Macro](#step-6-dsl-module--grammar-block-macro)
7. [Step 7: DSL Unit Tests — Expression Transformation](#step-7-dsl-unit-tests--expression-transformation)
8. [Step 8: DSL Unit Tests — Grammar Macro](#step-8-dsl-unit-tests--grammar-macro)
9. [Step 9: DSL Equivalence Tests](#step-9-dsl-equivalence-tests)
10. [Step 10: Rewrite Examples Using DSL](#step-10-rewrite-examples-using-dsl)
11. [Step 11: DSL Error Handling Tests](#step-11-dsl-error-handling-tests)
12. [Step 12: Full Test Suite Pass and Cleanup](#step-12-full-test-suite-pass-and-cleanup)

---

## Step 1: Runner Module

**Goal:** Create `src/treenimph/runner.nim` — a `run()` proc that replaces the manual `validateOrRaise()` + `echo renderGrammarJs()` pattern.

**File:** `src/treenimph/runner.nim`

```nim
import std/[os, parseopt, strutils]

import ./diagnostics
import ./exporter
import ./model
import ./render_js
import ./validate

type
  RunAction = enum
    raPrintJs
    raSummary
    raValidate
    raExport

proc run*(g: Grammar) =
  ## Entry point for grammar files. Validates the grammar, parses CLI
  ## arguments, and dispatches the requested action.
  ##
  ## CLI options:
  ##   (no options)        Print grammar.js to stdout
  ##   --export <dir>      Export full tree-sitter package to directory
  ##   --summary           Print grammar summary
  ##   --validate          Validate only (exit 0 = clean, exit 1 = errors)
  ##   --overwrite         Allow overwriting existing files (with --export)
  ##   --run-generate      Run tree-sitter generate after export (with --export)
  ##   --no-query-stubs    Skip generating empty query stubs (with --export)

  # 1. Validate
  let diags = g.validate()
  var hasErrors = false
  for d in diags:
    if d.kind == dkError:
      hasErrors = true
      stderr.writeLine $d
    elif d.kind == dkWarning:
      stderr.writeLine $d

  if hasErrors:
    quit(1)

  # 2. Parse CLI args
  var action = raPrintJs
  var exportDir = ""
  var overwrite = true
  var runGenerate = false
  var writeQueryStubs = true

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption:
      case p.key
      of "export":
        action = raExport
        exportDir = p.val
        if exportDir.len == 0:
          # Value might be the next argument
          p.next()
          if p.kind == cmdArgument:
            exportDir = p.key
          else:
            stderr.writeLine "Error: --export requires a directory argument"
            quit(1)
      of "summary":
        action = raSummary
      of "validate":
        action = raValidate
      of "overwrite":
        overwrite = true
      of "no-overwrite":
        overwrite = false
      of "run-generate":
        runGenerate = true
      of "no-query-stubs":
        writeQueryStubs = false
      else:
        stderr.writeLine "Unknown option: --" & p.key
        quit(1)
    of cmdShortOption:
      stderr.writeLine "Unknown option: -" & p.key
      quit(1)
    of cmdArgument:
      # If no --export flag was given but an argument is present,
      # treat it as an export directory
      if action == raPrintJs:
        action = raExport
        exportDir = p.key

  # 3. Execute
  case action
  of raPrintJs:
    echo g.renderGrammarJs()
  of raSummary:
    echo g.summary()
  of raValidate:
    echo "Grammar \"" & g.name & "\" is valid."
  of raExport:
    if exportDir.len == 0:
      stderr.writeLine "Error: --export requires a directory argument"
      quit(1)
    let config = mkExportConfig(
      outDir = exportDir,
      runGenerate = runGenerate,
      writeQueryStubs = writeQueryStubs,
      overwrite = overwrite,
    )
    g.exportGrammar(config)
    echo "Exported grammar \"" & g.name & "\" to " & exportDir
```

### What to verify before moving on

- File compiles: `nim check -p:src src/treenimph/runner.nim`
- No import cycle issues

---

## Step 2: Wire Runner into Root Module

**Goal:** Add `runner` to the root `treenimph` module so `import treenimph` gains `run()`.

**File:** `src/treenimph.nim`

Add two lines — the import and the export. The file should become:

```nim
## TreeNimph — A Nim library for authoring Tree-sitter grammars
## as composable typed objects.

import treenimph/model
import treenimph/diagnostics
import treenimph/validate
import treenimph/render_js
import treenimph/render_package
import treenimph/exporter
import treenimph/helpers
import treenimph/runner

export model
export diagnostics
export validate
export render_js
export render_package
export exporter
export helpers
export runner
```

### What to verify before moving on

- `nim check -p:src src/treenimph.nim` succeeds
- All existing tests still pass: `nimble test`

---

## Step 3: Update Examples to Use `run()`

**Goal:** Replace the boilerplate at the end of each example with `run(grammar)`.

### `examples/simple_lang.nim`

```nim
import treenimph

let grammar = mkGrammar(
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

run(grammar)
```

### `examples/arithmetic.nim`

```nim
import treenimph

let grammar = mkGrammar(
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

run(grammar)
```

### `examples/json_like.nim`

```nim
import treenimph

let
  value = Ref("_value")
  comma = Text(",")

let grammar = mkGrammar(
  "json",
  extras = [Regex("\\s+")],
  rules = [
    mkRule("document", value),
    mkRule("_value", Choice(Ref("object"), Ref("array"), Ref("string"), Ref("number"), Ref("true"), Ref("false"), Ref("null"))),
    mkRule("object", Sequence(Text("{"), Optional(delimitedList(Ref("pair"), comma, trailing = true)), Text("}"))),
    mkRule("pair", Sequence(Field("key", Ref("string")), Text(":"), Field("value", value))),
    mkRule("array", Sequence(Text("["), Optional(delimitedList(value, comma, trailing = true)), Text("]"))),
    mkRule("string", Regex("\"[^\"]*\"")),
    mkRule("number", Regex("-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?")),
    mkRule("true", Text("true")),
    mkRule("false", Text("false")),
    mkRule("null", Text("null")),
  ],
)

run(grammar)
```

### What to verify before moving on

- Each example compiles and runs: `nim r -p:src examples/simple_lang.nim`
- Each example prints valid-looking `grammar.js` to stdout (same output as before)
- `nim r -p:src examples/simple_lang.nim --summary` prints a summary
- `nim r -p:src examples/simple_lang.nim --validate` prints "Grammar is valid."
- All existing tests still pass: `nimble test`

---

## Step 4: Runner Tests

**Goal:** Create `tests/test_runner.nim` to test the runner module.

The runner calls `quit()` and reads `commandLineParams()`, which makes it hard to unit-test directly. Instead, test the runner by compiling and executing example grammar files as subprocesses, checking their stdout/stderr/exit code.

**File:** `tests/test_runner.nim`

```nim
import std/[osproc, strutils, os]
import unittest

const examplesDir = "examples"
const srcFlag = "-p:src"

proc runGrammar(file: string, args: string = ""): tuple[output: string, exitCode: int] =
  ## Compile and run a grammar file, returning stdout+stderr and exit code.
  let cmd = "nim r --hints:off " & srcFlag & " " & (examplesDir / file) & " " & args
  execCmdEx(cmd)

suite "runner — default action (print grammar.js)":
  test "simple_lang prints grammar.js":
    let (output, code) = runGrammar("simple_lang.nim")
    check code == 0
    check output.contains("module.exports = grammar")
    check output.contains("simple_lang")

  test "arithmetic prints grammar.js":
    let (output, code) = runGrammar("arithmetic.nim")
    check code == 0
    check output.contains("module.exports = grammar")

  test "json_like prints grammar.js":
    let (output, code) = runGrammar("json_like.nim")
    check code == 0
    check output.contains("module.exports = grammar")

suite "runner — --summary":
  test "simple_lang summary":
    let (output, code) = runGrammar("simple_lang.nim", "--summary")
    check code == 0
    check output.contains("Grammar: simple_lang")
    check output.contains("rules")

suite "runner — --validate":
  test "simple_lang validates":
    let (output, code) = runGrammar("simple_lang.nim", "--validate")
    check code == 0
    check output.contains("valid")

suite "runner — --export":
  test "simple_lang exports to temp dir":
    let tmpDir = getTempDir() / "treenimph_runner_test"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    let (output, code) = runGrammar("simple_lang.nim", "--export " & tmpDir)
    check code == 0
    check fileExists(tmpDir / "grammar.js")
    check fileExists(tmpDir / "package.json")
    check fileExists(tmpDir / "tree-sitter.json")
    check dirExists(tmpDir / "queries")
```

### What to verify before moving on

- `nim r -p:src tests/test_runner.nim` — all tests pass
- `nimble test` — all tests pass (including existing tests)

---

## Step 5: DSL Module — Scaffold and Expression Transformer

**Goal:** Create `src/treenimph/dsl.nim` with the core AST transformation logic. This step builds the `transformExpr` proc that recursively rewrites DSL syntax into raw API calls. The `grammar` macro itself comes in Step 6.

This is the most complex piece. Read carefully.

**File:** `src/treenimph/dsl.nim`

```nim
import std/[macros, sets, strutils]

# Re-export everything so `import treenimph/dsl` is batteries-included
import ../treenimph
export treenimph

proc isReservedConfigName(name: string): bool =
  ## Returns true if the name is a grammar-level config key, not a rule name.
  name in ["extras", "word", "conflicts", "supertypes", "inline",
           "externals", "scannerPath", "queryFiles"]

proc flattenInfix(node: NimNode, op: string): seq[NimNode] =
  ## Flattens left-associative infix chains.
  ## `a | b | c` parses as `(a | b) | c`, this returns @[a, b, c].
  if node.kind == nnkInfix and node[0].eqIdent(op):
    result = flattenInfix(node[1], op) & flattenInfix(node[2], op)
  else:
    result = @[node]

proc transformExpr(node: NimNode, letBound: HashSet[string]): NimNode =
  ## Recursively transforms a DSL expression AST node into raw API calls.
  ##
  ## Transformation rules:
  ##   bare ident (not let-bound)     -> Ref("name")
  ##   bare ident (let-bound)         -> left as-is (variable reference)
  ##   string literal                 -> Text("value")
  ##   re"pattern"                    -> Regex("pattern")
  ##   [a, b, c]                      -> Sequence(a', b', c')
  ##   a | b | c                      -> Choice(a', b', c')
  ##   ?x                             -> Optional(x')
  ##   *x                             -> ZeroOrMore(x')
  ##   +x                             -> OneOrMore(x')
  ##   name@expr                      -> Field("name", expr')
  ##   prec(n, x)                     -> Prec(n, x')
  ##   prec_left(n, x)                -> PrecLeft(n, x')
  ##   prec_right(n, x)               -> PrecRight(n, x')
  ##   prec_dynamic(n, x)             -> PrecDynamic(n, x')
  ##   token(x)                       -> Token(x')
  ##   immediate_token(x)             -> ImmediateToken(x')
  ##   alias(name, x, ...)            -> Alias(name, x', ...)
  ##   other_func(args...)            -> other_func(args'...)  (passthrough)
  ##   (x)                            -> x'  (unwrap parens)

  case node.kind

  of nnkIdent, nnkSym:
    # Bare identifier
    let name = node.strVal
    if name in letBound:
      # Let-bound variable — leave as-is
      return node
    else:
      # Rule reference
      return newCall(ident("Ref"), newStrLitNode(name))

  of nnkStrLit..nnkTripleStrLit:
    # String literal -> Text("value")
    return newCall(ident("Text"), node)

  of nnkCallStrLit:
    # re"pattern" -> Regex("pattern")
    if node[0].eqIdent("re"):
      return newCall(ident("Regex"), node[1])
    else:
      # Unknown generalized string literal — pass through
      return node

  of nnkBracket:
    # [a, b, c] -> Sequence(a', b', c')
    if node.len == 0:
      error("Empty brackets [] are not allowed — a sequence must have at least one item", node)
    if node.len == 1:
      # Single-element bracket — unwrap, no Sequence needed
      return transformExpr(node[0], letBound)
    var args = newNimNode(nnkArgList)
    for child in node:
      args.add transformExpr(child, letBound)
    result = newCall(ident("Sequence"))
    for i in 0 ..< args.len:
      result.add args[i]
    return result

  of nnkInfix:
    let op = node[0].strVal

    if op == "|":
      # a | b | c -> Choice(a', b', c')
      let leaves = flattenInfix(node, "|")
      result = newCall(ident("Choice"))
      for leaf in leaves:
        result.add transformExpr(leaf, letBound)
      return result

    elif op == "@":
      # name@expr -> Field("name", expr')
      let lhs = node[1]
      if lhs.kind != nnkIdent:
        error("Left side of @ must be a field name (bare identifier), got " & $lhs.kind, lhs)
      let fieldName = lhs.strVal
      let fieldExpr = transformExpr(node[2], letBound)
      return newCall(ident("Field"), newStrLitNode(fieldName), fieldExpr)

    else:
      # Unknown infix operator — transform both sides and preserve
      result = newNimNode(nnkInfix)
      result.add node[0]  # operator
      result.add transformExpr(node[1], letBound)
      result.add transformExpr(node[2], letBound)
      return result

  of nnkPrefix:
    let op = node[0].strVal

    if op == "?":
      return newCall(ident("Optional"), transformExpr(node[1], letBound))
    elif op == "*":
      return newCall(ident("ZeroOrMore"), transformExpr(node[1], letBound))
    elif op == "+":
      return newCall(ident("OneOrMore"), transformExpr(node[1], letBound))
    else:
      # Unknown prefix — transform operand and preserve
      result = newNimNode(nnkPrefix)
      result.add node[0]
      result.add transformExpr(node[1], letBound)
      return result

  of nnkCall, nnkCommand:
    # Function call — check for recognized DSL calls
    let funcName = if node[0].kind == nnkIdent: node[0].strVal else: ""

    case funcName
    of "prec":
      # prec(level, expr) -> Prec(level, expr')
      if node.len < 3:
        error("prec() requires at least 2 arguments: prec(level, expr)", node)
      let level = node[1]  # pass through as-is (integer literal)
      let body = transformExpr(node[2], letBound)
      result = newCall(ident("Prec"), level, body)
      # Pass through optional named args (e.g. assoc)
      for i in 3 ..< node.len:
        result.add node[i]
      return result

    of "prec_left":
      if node.len < 3:
        error("prec_left() requires at least 2 arguments: prec_left(level, expr)", node)
      return newCall(ident("PrecLeft"), node[1], transformExpr(node[2], letBound))

    of "prec_right":
      if node.len < 3:
        error("prec_right() requires at least 2 arguments: prec_right(level, expr)", node)
      return newCall(ident("PrecRight"), node[1], transformExpr(node[2], letBound))

    of "prec_dynamic":
      if node.len < 3:
        error("prec_dynamic() requires at least 2 arguments: prec_dynamic(level, expr)", node)
      return newCall(ident("PrecDynamic"), node[1], transformExpr(node[2], letBound))

    of "token":
      if node.len < 2:
        error("token() requires 1 argument", node)
      return newCall(ident("Token"), transformExpr(node[1], letBound))

    of "immediate_token":
      if node.len < 2:
        error("immediate_token() requires 1 argument", node)
      return newCall(ident("ImmediateToken"), transformExpr(node[1], letBound))

    of "alias":
      # alias(name, expr) or alias(name, expr, named = false)
      if node.len < 3:
        error("alias() requires at least 2 arguments: alias(name, expr)", node)
      let aliasName = node[1]  # keep as string literal
      let aliasExpr = transformExpr(node[2], letBound)
      result = newCall(ident("Alias"), aliasName, aliasExpr)
      # Pass through optional named params (e.g., named = false)
      for i in 3 ..< node.len:
        result.add node[i]
      return result

    else:
      # Unknown function call (helpers like delimitedList, balanced, etc.)
      # Transform all positional arguments, pass through named arguments as-is
      result = newNimNode(nnkCall)
      result.add node[0]  # function name
      for i in 1 ..< node.len:
        let arg = node[i]
        if arg.kind == nnkExprEqExpr:
          # Named argument like `trailing = true` — transform the value
          var namedArg = newNimNode(nnkExprEqExpr)
          namedArg.add arg[0]  # parameter name
          namedArg.add transformExpr(arg[1], letBound)
          result.add namedArg
        else:
          result.add transformExpr(arg, letBound)
      return result

  of nnkPar:
    # Parenthesized expression — unwrap
    if node.len == 1:
      return transformExpr(node[0], letBound)
    # Tuple literal or multi-expression — transform each
    result = newNimNode(nnkPar)
    for child in node:
      result.add transformExpr(child, letBound)
    return result

  of nnkIntLit..nnkFloat128Lit:
    # Numeric literals — pass through as-is
    return node

  of nnkNilLit:
    return node

  else:
    # Anything else — pass through unchanged with a warning-level hint
    # (This handles edge cases we haven't anticipated)
    return node
```

### What to verify before moving on

- `nim check -p:src src/treenimph/dsl.nim` succeeds
- No import cycles
- All existing tests still pass: `nimble test`

**Note:** The `transformExpr` proc is not yet called by anything — that comes in Step 6. At this point we're just verifying it compiles.

---

## Step 6: DSL Module — Grammar Block Macro

**Goal:** Add the `grammar` block macro to `src/treenimph/dsl.nim`. This macro processes the DSL block and emits the full program (grammar construction + `run()` call).

**Append to:** `src/treenimph/dsl.nim` (after the `transformExpr` proc)

```nim
proc transformConfigValue(key: string, value: NimNode, letBound: HashSet[string]): NimNode =
  ## Transforms config values. Most config values need special handling
  ## because they expect different types than rule bodies.
  case key
  of "extras":
    # extras = [expr1, expr2, ...] -> seq of Expr
    # Transform each element but don't wrap in Sequence
    if value.kind == nnkBracket:
      result = newNimNode(nnkBracket)
      for child in value:
        result.add transformExpr(child, letBound)
      return result
    else:
      return transformExpr(value, letBound)

  of "word":
    # word = identifier -> some("identifier")
    if value.kind == nnkIdent:
      return newCall(ident("some"), newStrLitNode(value.strVal))
    else:
      error("word must be a bare identifier (rule name)", value)

  of "conflicts":
    # conflicts = [[rule1, rule2], [rule3, rule4]] -> seq[seq[string]]
    if value.kind != nnkBracket:
      error("conflicts must be a bracket list of bracket lists", value)
    result = newNimNode(nnkBracket)
    for group in value:
      if group.kind != nnkBracket:
        error("Each conflict group must be a bracket list of identifiers", group)
      var names = newNimNode(nnkPrefix)
      names.add ident("@")
      var bracketNode = newNimNode(nnkBracket)
      for item in group:
        if item.kind != nnkIdent:
          error("Conflict entries must be bare identifiers (rule names)", item)
        bracketNode.add newStrLitNode(item.strVal)
      names.add bracketNode
      result.add names
    return result

  of "supertypes", "inline":
    # supertypes = [ident1, ident2] -> seq[string]
    if value.kind != nnkBracket:
      error(key & " must be a bracket list of identifiers", value)
    result = newNimNode(nnkBracket)
    for item in value:
      if item.kind != nnkIdent:
        error(key & " entries must be bare identifiers (rule names)", item)
      result.add newStrLitNode(item.strVal)
    return result

  of "externals":
    # externals = [expr1, expr2] -> seq of Expr
    if value.kind == nnkBracket:
      result = newNimNode(nnkBracket)
      for child in value:
        result.add transformExpr(child, letBound)
      return result
    else:
      return transformExpr(value, letBound)

  of "scannerPath":
    # scannerPath = "path/to/scanner.c" -> some("path/to/scanner.c")
    if value.kind in {nnkStrLit..nnkTripleStrLit}:
      return newCall(ident("some"), value)
    else:
      error("scannerPath must be a string literal", value)

  of "queryFiles":
    # queryFiles = <expr> -> some(<expr>)
    # Pass through as-is (user provides a QueryFiles value)
    return newCall(ident("some"), value)

  else:
    error("Unknown config key: " & key, value)
    return value

macro grammar*(name: string, body: untyped): untyped =
  ## The TreeNimph DSL macro. Transforms a block of grammar definitions
  ## into a complete grammar program with validation and CLI dispatch.
  ##
  ## Usage:
  ##   grammar "my_lang":
  ##     source_file = *statement
  ##     statement = let_stmt | expr_stmt
  ##     let_stmt = ["let", name@identifier, "=", value@expression, ";"]
  ##     identifier = re"[a-zA-Z_][a-zA-Z0-9_]*"

  expectKind body, nnkStmtList

  # Collect let-bound names, config assignments, and rules
  var letBound: HashSet[string]
  var letSections: seq[NimNode]      # transformed let sections to emit
  var configArgs: seq[NimNode]       # named args for mkGrammar
  var ruleExprs: seq[NimNode]        # mkRule(...) calls

  # Pass 1: categorize each statement
  for stmt in body:
    case stmt.kind

    of nnkLetSection:
      # let binding — track names and transform RHS
      var newLetSection = newNimNode(nnkLetSection)
      for def in stmt:
        expectKind def, nnkIdentDefs
        let varName = def[0]
        if varName.kind != nnkIdent:
          error("let binding name must be a bare identifier", varName)
        letBound.incl varName.strVal

        # Transform the RHS value
        let rhs = def[2]  # [0]=name, [1]=type (empty), [2]=value
        let transformedRhs = transformExpr(rhs, letBound)

        var newDef = newNimNode(nnkIdentDefs)
        newDef.add varName
        newDef.add def[1]  # type annotation (usually empty)
        newDef.add transformedRhs
        newLetSection.add newDef

      letSections.add newLetSection

    of nnkAsgn:
      # name = expr — either config or rule
      let lhs = stmt[0]
      let rhs = stmt[1]

      if lhs.kind != nnkIdent:
        error("Left-hand side must be a bare identifier (rule name or config key)", lhs)

      let lhsName = lhs.strVal

      if isReservedConfigName(lhsName):
        # Grammar-level config
        let configValue = transformConfigValue(lhsName, rhs, letBound)
        configArgs.add newNimNode(nnkExprEqExpr).add(ident(lhsName), configValue)
      else:
        # Rule definition
        let ruleBody = transformExpr(rhs, letBound)
        ruleExprs.add newCall(ident("mkRule"), newStrLitNode(lhsName), ruleBody)

    of nnkCommentStmt:
      # Skip comments
      discard

    else:
      error("Unexpected statement in grammar block. Expected: rule definition (name = expr), " &
            "let binding, or config assignment. Got: " & $stmt.kind, stmt)

  # Validate we have at least one rule
  if ruleExprs.len == 0:
    error("Grammar must contain at least one rule definition", body)

  # Build the rules array
  var rulesArray = newNimNode(nnkBracket)
  for r in ruleExprs:
    rulesArray.add r

  # Build the mkGrammar call
  var grammarCall = newCall(ident("mkGrammar"), name)
  grammarCall.add newNimNode(nnkExprEqExpr).add(ident("rules"), rulesArray)
  for arg in configArgs:
    grammarCall.add arg

  # Emit the full program
  result = newStmtList()

  # Emit let bindings first
  for letSec in letSections:
    result.add letSec

  # Emit: let grammar = mkGrammar(...)
  var grammarLet = newNimNode(nnkLetSection)
  var grammarDef = newNimNode(nnkIdentDefs)
  grammarDef.add ident("grammar")
  grammarDef.add newEmptyNode()  # no type annotation
  grammarDef.add grammarCall
  grammarLet.add grammarDef
  result.add grammarLet

  # Emit: run(grammar)
  result.add newCall(ident("run"), ident("grammar"))
```

### What to verify before moving on

- `nim check -p:src src/treenimph/dsl.nim` succeeds
- Create a quick smoke test file `tests/smoke_dsl.nim`:

```nim
# Minimal smoke test — just verifies the DSL compiles and produces output
import treenimph/dsl

grammar "smoke_test":
  source = *statement
  statement = identifier | number
  identifier = re"[a-zA-Z_]+"
  number = re"[0-9]+"
```

Run it: `nim r -p:src tests/smoke_dsl.nim`

Expected: prints a valid `grammar.js` to stdout containing `module.exports = grammar`, `smoke_test`, and rule definitions for `source`, `statement`, `identifier`, `number`.

Delete `tests/smoke_dsl.nim` after verifying — proper tests come in the next steps.

---

## Step 7: DSL Unit Tests — Expression Transformation

**Goal:** Create `tests/test_dsl.nim` with thorough tests for each transformation rule. These tests use `macros.parseExpr` / `macros.parseStmt` and `expandMacros` to verify the macro's output.

Since the `transformExpr` proc operates on `NimNode` at compile time, we test it indirectly by writing DSL code and checking that the resulting `Grammar` objects have the expected structure.

**File:** `tests/test_dsl.nim`

```nim
import std/[options, strutils]
import unittest

import treenimph/model
import treenimph/validate
import treenimph/render_js
import treenimph/helpers
import treenimph/runner
import treenimph/dsl {.all.}

# We cannot call `run()` in tests because it calls quit().
# Instead, we define a helper macro that builds the grammar but returns
# the Grammar object instead of calling run().
macro testGrammar*(name: string, body: untyped): untyped =
  ## Like `grammar` but returns the Grammar object instead of calling run().
  ## Used for testing.
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

  test "underscore-prefixed identifier":
    let g = testGrammar "test":
      source = _hidden
      _hidden = re"[a-z]+"
    check g.rules[0].body.kind == ekRef
    check g.rules[0].body.refName == "_hidden"

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
    # Single-element bracket should NOT create a Sequence
    check g.rules[0].body.kind == ekRegex

  test "bracket with mixed types":
    let g = testGrammar "test":
      source = ["let", identifier, "=", expression]
      identifier = re"[a-z]+"
      expression = re"[0-9]+"
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items[0].kind == ekText  # "let"
    check g.rules[0].body.items[1].kind == ekRef    # identifier
    check g.rules[0].body.items[2].kind == ekText   # "="
    check g.rules[0].body.items[3].kind == ekRef    # expression

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
    # a | b | c parses as (a | b) | c — should flatten to Choice(a, b, c)
    check g.rules[0].body.kind == ekChoice
    check g.rules[0].body.items.len == 3

  test "choice of sequences":
    let g = testGrammar "test":
      source = ["a", "b"] | ["c", "d"]
      # This is not valid as-is because | has lower precedence than comma in brackets
      # But the brackets group correctly: Choice(Sequence("a","b"), Sequence("c","d"))
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
    # myExpr should resolve to the variable (which holds Ref("identifier"))
    # so source's body should be Ref("identifier"), not Ref("myExpr")
    check g.rules[0].body.kind == ekRef
    check g.rules[0].body.refName == "identifier"

  test "let-bound string becomes Text":
    let g = testGrammar "test":
      let sep = ","
      source = [identifier, sep, identifier]
      identifier = re"[a-z]+"
    # sep is let-bound to Text(","), used in sequence
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
    # delimitedList(Ref("item"), Text(",")) should produce a Sequence
    check g.rules[0].body.kind == ekSequence

  test "delimitedList with trailing":
    let g = testGrammar "test":
      source = delimitedList(item, ",", trailing = true)
      item = re"[a-z]+"
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items.len == 3  # item, repeat, optional

  test "balanced with transformed args":
    let g = testGrammar "test":
      source = balanced("(", ")", expr)
      expr = re"[a-z]+"
    check g.rules[0].body.kind == ekSequence
    check g.rules[0].body.items[0].kind == ekText
    check g.rules[0].body.items[0].textValue == "("

suite "DSL — hidden rules":
  test "underscore-prefixed rule name sets hidden":
    let g = testGrammar "test":
      source = _value
      _value = "x"
    check g.rules[1].hidden == true
    check g.rules[1].name == "_value"

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
      supertypes = [_expression]
      source = _expression
      _expression = "x"
    check g.supertypes.len == 1
    check g.supertypes[0] == "_expression"

  test "inline":
    let g = testGrammar "test":
      inline = [_helper]
      source = _helper
      _helper = "x"
    check g.inline.len == 1
    check g.inline[0] == "_helper"

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
```

### Important implementation note

The `testGrammar` macro above duplicates the core logic of the `grammar` macro but returns the `Grammar` object instead of calling `run()`. This is necessary because `run()` calls `quit()` and reads CLI args, which breaks test harnesses.

**Alternative approach:** If you'd prefer to avoid the duplication, you could refactor the `grammar` macro to call a separate internal proc that builds the Grammar, and have `testGrammar` call that same proc. However, since macros work at compile time and the proc is already compile-time code, the duplication above is the simplest approach for now. Refactoring to reduce duplication is acceptable as a follow-up.

### What to verify before moving on

- `nim r -p:src tests/test_dsl.nim` — all tests pass
- `nimble test` — all tests pass

---

## Step 8: DSL Unit Tests — Grammar Macro

**Goal:** Test the full `grammar` macro end-to-end by compiling and running DSL grammar files as subprocesses (similar to Step 4's runner tests). This verifies that the macro generates correct programs that produce valid output.

**File:** `tests/test_dsl_integration.nim`

```nim
import std/[os, osproc, strutils, tempfiles]
import unittest

const srcFlag = "-p:src"

proc compileAndRun(code: string, args: string = ""): tuple[output: string, exitCode: int] =
  ## Write a grammar file to a temp file, compile and run it, return output.
  let (tmpFile, tmpPath) = createTempFile("treenimph_dsl_test_", ".nim")
  tmpFile.write(code)
  tmpFile.close()
  defer: removeFile(tmpPath)

  let cmd = "nim r --hints:off " & srcFlag & " " & tmpPath & " " & args
  execCmdEx(cmd)

suite "DSL integration — simple grammars":
  test "minimal grammar produces valid grammar.js":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "minimal":
  source = re"[a-z]+"
""")
    check code == 0
    check output.contains("module.exports = grammar")
    check output.contains("'minimal'")
    check output.contains("source: $ =>")

  test "grammar with sequences and choices":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "test_lang":
  source = *statement
  statement = let_stmt | expr_stmt
  let_stmt = ["let", name@identifier, "=", value@expression, ";"]
  expr_stmt = [expression, ";"]
  expression = identifier | number
  identifier = re"[a-zA-Z_][a-zA-Z0-9_]*"
  number = re"[0-9]+"
""")
    check code == 0
    check output.contains("module.exports = grammar")
    check output.contains("'test_lang'")
    check output.contains("repeat($.statement)")
    check output.contains("choice($.let_stmt, $.expr_stmt)")
    check output.contains("field('name', $.identifier)")
    check output.contains("'let'")
    check output.contains("';'")

  test "grammar with let bindings":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "json":
  extras = [re"\s+"]

  let value = _value
  let comma = ","

  document = value
  _value = object | string | number
  object = ["{", ?delimitedList(pair, comma, trailing = true), "}"]
  pair = [key@string, ":", val@value]
  string = re"\"[^\"]*\""
  number = re"[0-9]+"
""")
    check code == 0
    check output.contains("module.exports = grammar")
    check output.contains("extras: $ => [")
    check output.contains("/\\s+/")

  test "grammar with precedence":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "arith":
  expression = number | binary_expression
  binary_expression = prec_left(1, [left@expression, operator@("+" | "-"), right@expression])
  number = re"[0-9]+"
""")
    check code == 0
    check output.contains("prec.left(1")
    check output.contains("field('left'")
    check output.contains("field('operator'")

suite "DSL integration — CLI flags":
  test "--summary flag":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "demo":
  source = "x"
""", "--summary")
    check code == 0
    check output.contains("Grammar: demo")

  test "--validate flag":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "demo":
  source = "x"
""", "--validate")
    check code == 0
    check output.contains("valid")

  test "--export flag":
    let tmpDir = createTempDir("treenimph_dsl_export_", "")
    defer: removeDir(tmpDir)

    let exportDir = tmpDir / "output"
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "exported":
  source = *statement
  statement = "x"
""", "--export " & exportDir)
    check code == 0
    check fileExists(exportDir / "grammar.js")
    check fileExists(exportDir / "package.json")
    check fileExists(exportDir / "tree-sitter.json")

suite "DSL integration — grammar config sections":
  test "word, extras, supertypes, inline, conflicts":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "full_config":
  extras = [re"\s+"]
  word = identifier
  supertypes = [_expression]
  inline = [_helper]
  conflicts = [[_expression, binary_expression]]

  source = *_expression
  _expression = identifier | binary_expression
  binary_expression = prec_left(1, [_expression, "+", _expression])
  identifier = re"[a-zA-Z_]+"
  _helper = re"\s+"
""")
    check code == 0
    check output.contains("word: $ => $.identifier")
    check output.contains("extras: $ => [")
    check output.contains("supertypes: $ => [")
    check output.contains("inline: $ => [")
    check output.contains("conflicts: $ => [")
```

### What to verify before moving on

- `nim r -p:src tests/test_dsl_integration.nim` — all tests pass
- `nimble test` — all tests still pass

---

## Step 9: DSL Equivalence Tests

**Goal:** Prove that DSL grammars produce identical `grammar.js` output to their raw API equivalents. This is the critical correctness guarantee.

**File:** `tests/test_dsl_equivalence.nim`

```nim
import std/[options, strutils]
import unittest

import treenimph/model
import treenimph/helpers
import treenimph/render_js
import treenimph/validate

# Import DSL test helper
import treenimph/dsl {.all.}

# Reuse testGrammar from test_dsl.nim — or redefine it here.
# For self-containment, we redefine it:
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
    # Raw API version
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

    # DSL version
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
    let rawValue = Ref("_value")
    let rawComma = Text(",")
    let rawGrammar = mkGrammar(
      "json",
      extras = [Regex("\\s+")],
      rules = [
        mkRule("document", rawValue),
        mkRule("_value", Choice(Ref("object"), Ref("array"), Ref("string"), Ref("number"), Ref("true"), Ref("false"), Ref("null"))),
        mkRule("object", Sequence(Text("{"), Optional(delimitedList(Ref("pair"), rawComma, trailing = true)), Text("}"))),
        mkRule("pair", Sequence(Field("key", Ref("string")), Text(":"), Field("value", rawValue))),
        mkRule("array", Sequence(Text("["), Optional(delimitedList(rawValue, rawComma, trailing = true)), Text("]"))),
        mkRule("string", Regex("\"[^\"]*\"")),
        mkRule("number", Regex("-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?")),
        mkRule("true", Text("true")),
        mkRule("false", Text("false")),
        mkRule("null", Text("null")),
      ],
    )
    rawGrammar.validateOrRaise()

    let dslGrammar = testGrammar "json":
      extras = [re"\\s+"]

      let value = _value
      let comma = ","

      document = value
      _value = object | array | string | number | true_lit | false_lit | null_lit
      object = ["{", ?delimitedList(pair, comma, trailing = true), "}"]
      pair = [key@string, ":", val@value]
      array = ["[", ?delimitedList(value, comma, trailing = true), "]"]
      string = re"\"[^\"]*\""
      number = re"-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?"
      true_lit = "true"
      false_lit = "false"
      null_lit = "null"
    dslGrammar.validateOrRaise()

    # NOTE: The DSL version uses different rule names for true/false/null
    # (true_lit vs true) because `true` is a Nim keyword. This means the
    # rendered grammar.js will differ in rule names. The equivalence test
    # here validates the structural transformation is correct, but the
    # rule name difference is expected and acceptable.
    #
    # If exact output match is required, the raw grammar must use the
    # same names as the DSL grammar.
    #
    # For this test, we rebuild the raw grammar with matching names:
    let rawGrammarMatching = mkGrammar(
      "json",
      extras = [Regex("\\s+")],
      rules = [
        mkRule("document", rawValue),
        mkRule("_value", Choice(Ref("object"), Ref("array"), Ref("string"), Ref("number"), Ref("true_lit"), Ref("false_lit"), Ref("null_lit"))),
        mkRule("object", Sequence(Text("{"), Optional(delimitedList(Ref("pair"), rawComma, trailing = true)), Text("}"))),
        mkRule("pair", Sequence(Field("key", Ref("string")), Text(":"), Field("val", rawValue))),
        mkRule("array", Sequence(Text("["), Optional(delimitedList(rawValue, rawComma, trailing = true)), Text("]"))),
        mkRule("string", Regex("\"[^\"]*\"")),
        mkRule("number", Regex("-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?")),
        mkRule("true_lit", Text("true")),
        mkRule("false_lit", Text("false")),
        mkRule("null_lit", Text("null")),
      ],
    )

    check rawGrammarMatching.renderGrammarJs() == dslGrammar.renderGrammarJs()
```

### Important note about Nim keywords

The JSON equivalence test reveals an important limitation: Nim keywords (`true`, `false`, `nil`, `type`, `object`, `string`, etc.) cannot be used as bare identifiers in the DSL. When a grammar needs a rule named `true`, the DSL user must choose an alternative name like `true_lit`.

However, note that some of these (like `object`, `string`) may actually work as identifiers in Nim depending on context. Test each case. If this becomes a significant pain point, a future enhancement could support backtick-quoted identifiers (`` `true` ``) in the DSL macro — but this is out of scope for the initial implementation.

### What to verify before moving on

- `nim r -p:src tests/test_dsl_equivalence.nim` — all tests pass
- `nimble test` — all tests pass

---

## Step 10: Rewrite Examples Using DSL

**Goal:** Create DSL versions of all three examples. Preserve the raw API versions in `examples/raw/`.

### Step 10a: Move raw examples

```bash
mkdir -p examples/raw
cp examples/simple_lang.nim examples/raw/simple_lang.nim
cp examples/arithmetic.nim examples/raw/arithmetic.nim
cp examples/json_like.nim examples/raw/json_like.nim
```

### Step 10b: Rewrite `examples/simple_lang.nim`

```nim
import treenimph/dsl

grammar "simple_lang":
  source_file = *statement
  statement = let_stmt | expr_stmt
  let_stmt = ["let", name@identifier, "=", value@expression, ";"]
  expr_stmt = [expression, ";"]
  expression = identifier | number
  identifier = re"[a-zA-Z_][a-zA-Z0-9_]*"
  number = re"[0-9]+"
```

### Step 10c: Rewrite `examples/arithmetic.nim`

```nim
import treenimph/dsl

grammar "arithmetic":
  expression = number | binary_expression | parenthesized_expression
  binary_expression = prec_left(1, [
    left@expression,
    operator@("+" | "-" | "*" | "/"),
    right@expression,
  ])
  parenthesized_expression = balanced("(", ")", expression)
  number = re"[0-9]+"
```

### Step 10d: Rewrite `examples/json_like.nim`

```nim
import treenimph/dsl

grammar "json":
  extras = [re"\\s+"]

  let value = _value
  let comma = ","

  document = value
  _value = json_object | array | string | number | true_lit | false_lit | null_lit
  json_object = ["{", ?delimitedList(pair, comma, trailing = true), "}"]
  pair = [key@string, ":", val@value]
  array = ["[", ?delimitedList(value, comma, trailing = true), "]"]
  string = re"\"[^\"]*\""
  number = re"-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?"
  true_lit = "true"
  false_lit = "false"
  null_lit = "null"
```

**Note:** `object` is a Nim keyword, so we use `json_object` instead. Similarly, `true`/`false`/`null` are Nim keywords, so we use `true_lit`/`false_lit`/`null_lit`. `string` may also cause issues — test it and rename to `json_string` if needed.

### What to verify before moving on

- Each DSL example compiles and runs:
  - `nim r -p:src examples/simple_lang.nim`
  - `nim r -p:src examples/arithmetic.nim`
  - `nim r -p:src examples/json_like.nim`
- Each produces valid `grammar.js` output
- Each raw example still works:
  - `nim r -p:src examples/raw/simple_lang.nim`
  - `nim r -p:src examples/raw/arithmetic.nim`
  - `nim r -p:src examples/raw/json_like.nim`
- `nimble test` — all tests pass

---

## Step 11: DSL Error Handling Tests

**Goal:** Verify that the macro produces clear compile-time errors for invalid DSL input.

**File:** `tests/test_dsl_errors.nim`

These tests verify that invalid DSL code fails to compile with appropriate error messages. We do this by compiling code snippets and checking the exit code and error output.

```nim
import std/[os, osproc, strutils, tempfiles]
import unittest

const srcFlag = "-p:src"

proc compileOnly(code: string): tuple[output: string, exitCode: int] =
  ## Write code to a temp file and attempt to compile (not run) it.
  let (tmpFile, tmpPath) = createTempFile("treenimph_dsl_err_", ".nim")
  tmpFile.write(code)
  tmpFile.close()
  defer: removeFile(tmpPath)

  let cmd = "nim check --hints:off " & srcFlag & " " & tmpPath
  execCmdEx(cmd)

suite "DSL compile-time errors":
  test "empty grammar body fails":
    let (output, code) = compileOnly("""
import treenimph/dsl

grammar "empty":
  discard
""")
    check code != 0
    check output.contains("Unexpected statement") or output.contains("at least one rule")

  test "@ with non-identifier LHS fails":
    let (output, code) = compileOnly("""
import treenimph/dsl

grammar "bad_field":
  source = "bad"@identifier
  identifier = re"[a-z]+"
""")
    check code != 0
    check output.contains("field name") or output.contains("bare identifier")

  test "empty brackets fail":
    let (output, code) = compileOnly("""
import treenimph/dsl

grammar "bad_seq":
  source = []
""")
    check code != 0
    check output.contains("Empty brackets") or output.contains("at least one item")

  test "prec_left with missing args fails":
    let (output, code) = compileOnly("""
import treenimph/dsl

grammar "bad_prec":
  source = prec_left(1)
""")
    check code != 0
    check output.contains("requires") or output.contains("argument")
```

### What to verify before moving on

- `nim r -p:src tests/test_dsl_errors.nim` — all tests pass
- `nimble test` — all tests pass

---

## Step 12: Full Test Suite Pass and Cleanup

**Goal:** Ensure everything works together, update the nimble test task, and clean up.

### Step 12a: Update nimble test task

The current nimble file runs all `.nim` files in `tests/`. Verify that all new test files are picked up automatically. If any test files are in subdirectories, update the task.

Check: `nimble test` should run all tests, including:
- `tests/test_model.nim`
- `tests/test_validate.nim`
- `tests/test_render_js.nim`
- `tests/test_render_package.nim`
- `tests/test_helpers.nim`
- `tests/test_diagnostics.nim`
- `tests/test_examples.nim`
- `tests/test_export.nim`
- `tests/test_runner.nim` (new)
- `tests/test_dsl.nim` (new)
- `tests/test_dsl_integration.nim` (new)
- `tests/test_dsl_equivalence.nim` (new)
- `tests/test_dsl_errors.nim` (new)

### Step 12b: Verify all examples

```bash
# DSL examples
nim r -p:src examples/simple_lang.nim
nim r -p:src examples/arithmetic.nim
nim r -p:src examples/json_like.nim

# Raw examples (preserved)
nim r -p:src examples/raw/simple_lang.nim
nim r -p:src examples/raw/arithmetic.nim
nim r -p:src examples/raw/json_like.nim

# CLI flags
nim r -p:src examples/simple_lang.nim --summary
nim r -p:src examples/simple_lang.nim --validate
```

### Step 12c: Run full test suite

```bash
nimble test
```

All tests must pass. If any test fails, debug and fix before considering the implementation complete.

### Step 12d: Final file inventory

After all steps are complete, the project should have these new/modified files:

**New files:**
| File | Purpose |
|---|---|
| `src/treenimph/runner.nim` | `run()` proc with CLI arg parsing |
| `src/treenimph/dsl.nim` | `grammar` block macro + `transformExpr` + `testGrammar` |
| `tests/test_runner.nim` | Runner subprocess tests |
| `tests/test_dsl.nim` | DSL unit tests (expression transformation) |
| `tests/test_dsl_integration.nim` | DSL integration tests (compile + run grammar files) |
| `tests/test_dsl_equivalence.nim` | DSL vs raw API output equivalence tests |
| `tests/test_dsl_errors.nim` | DSL compile-time error tests |
| `examples/raw/simple_lang.nim` | Preserved raw API example |
| `examples/raw/arithmetic.nim` | Preserved raw API example |
| `examples/raw/json_like.nim` | Preserved raw API example |

**Modified files:**
| File | Change |
|---|---|
| `src/treenimph.nim` | Added `import/export runner` |
| `examples/simple_lang.nim` | Rewritten to use DSL |
| `examples/arithmetic.nim` | Rewritten to use DSL |
| `examples/json_like.nim` | Rewritten to use DSL |

**Unchanged files:**
| File |
|---|
| `src/treenimph/model.nim` |
| `src/treenimph/diagnostics.nim` |
| `src/treenimph/validate.nim` |
| `src/treenimph/render_js.nim` |
| `src/treenimph/render_package.nim` |
| `src/treenimph/exporter.nim` |
| `src/treenimph/helpers.nim` |
| All existing test files |

---

## Troubleshooting Guide

### Common issues you may encounter

**1. `re"..."` not recognized**

If the macro sees `re"pattern"` as something other than `nnkCallStrLit`, it may be because Nim is resolving `re` to something else (e.g., the `re` module from the standard library). Since we define our own transformation, this should not be an issue — but if it is, ensure that no `import re` is in scope.

**2. Nim keyword conflicts**

Bare identifiers in the DSL must be valid Nim identifiers that aren't keywords. Known conflicts:
- `true`, `false`, `nil` — use `true_lit`, `false_lit`, `nil_lit`
- `object` — use `json_object` or `obj`
- `type` — use `type_decl` or similar
- `string` — test this; it may work since `string` is a type, not a keyword in all contexts
- `import`, `export`, `return`, `if`, `else`, `while`, `for`, `case`, `of`, `proc`, `func`, `method`, `var`, `let`, `const`, `block`, `template`, `macro` — all reserved

If a grammar genuinely needs a rule called `true`, the user must use the raw API (`mkRule("true", Text("true"))`) for that specific rule, or use the DSL with an alternative name.

**3. `|` operator precedence issues**

If `a | b | c | d` produces incorrect nesting, check that `flattenInfix` is called in `transformExpr` for the `|` case. The flattening must recursively collect all leaves from the left-associative parse tree.

**4. `@` operator precedence relative to `|`**

In Nim, `@` (precedence 7) binds tighter than `|` (precedence 4). So `name@expr | other` parses as `(name@expr) | other` — correct. But `name@a | b` parses as `(name@a) | b`, meaning the field only captures `a`, not the choice. If the user wants `name@(a | b)`, they must use parentheses. This is the correct behavior — document it.

**5. Bracket sequences inside function calls**

`prec_left(1, [a, b, c])` — the brackets inside a function call argument should be parsed as `nnkBracket` by Nim. Verify this works correctly; if Nim interprets it as an array literal being passed to `prec_left`, the macro must still transform it. Test this case explicitly.

**6. `testGrammar` macro duplication**

The `testGrammar` macro in `test_dsl.nim` and `test_dsl_equivalence.nim` duplicates logic from the `grammar` macro. If you modify the `grammar` macro, you must update `testGrammar` to match. Consider extracting the shared logic into a compile-time proc that both macros call, but only do this if maintaining the duplication becomes burdensome.

**7. Named arguments to helpers**

`delimitedList(item, ",", trailing = true)` — the `trailing = true` is a named argument (`nnkExprEqExpr`). The macro must NOT transform the parameter name (`trailing`) as a rule reference. The code in `transformExpr` handles this by checking for `nnkExprEqExpr` in the call argument list and only transforming the value, not the name. Make sure this case is tested.

---

## Summary of Testing Strategy

| Test file | What it tests | How |
|---|---|---|
| `test_runner.nim` | Runner CLI behavior | Subprocess execution of examples |
| `test_dsl.nim` | Each DSL transformation rule | `testGrammar` macro → inspect Grammar objects |
| `test_dsl_integration.nim` | Full DSL grammars compile and run | Subprocess compilation of temp files |
| `test_dsl_equivalence.nim` | DSL output matches raw API output | Compare `renderGrammarJs()` strings |
| `test_dsl_errors.nim` | Invalid DSL produces compile errors | `nim check` on invalid code |
| Existing test files | Core library unchanged | `nimble test` regression |
