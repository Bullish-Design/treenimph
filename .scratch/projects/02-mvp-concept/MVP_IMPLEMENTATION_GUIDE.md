# TreeNimph MVP Implementation Guide

This guide provides step-by-step implementation instructions for every module in TreeNimph v1. Each section maps directly to the MVP Spec and includes exact code, file paths, decision rationale, and testing strategy. Implement in the order presented — each phase builds on the previous one.

---

## Table of Contents

1. [Project Setup](#1-project-setup)
2. [Phase 1: Core Model (`model.nim`)](#2-phase-1-core-model)
3. [Phase 2: Diagnostics (`diagnostics.nim`)](#3-phase-2-diagnostics)
4. [Phase 3: Validation (`validate.nim`)](#4-phase-3-validation)
5. [Phase 4: JS Rendering (`render_js.nim`)](#5-phase-4-js-rendering)
6. [Phase 5: Package Rendering (`render_package.nim`)](#6-phase-5-package-rendering)
7. [Phase 6: Helpers (`helpers.nim`)](#7-phase-6-helpers)
8. [Phase 7: Export (`exporter.nim`)](#8-phase-7-export)
9. [Phase 8: Public API (`treenimph.nim`)](#9-phase-8-public-api)
10. [Phase 9: Testing](#10-phase-9-testing)
11. [Phase 10: Examples](#11-phase-10-examples)
12. [Cross-Cutting Concerns](#12-cross-cutting-concerns)
13. [Implementation Checklist](#13-implementation-checklist)

---

## 1. Project Setup

### 1.1 Directory Structure

Create the following layout from the project root:

```
treenimph/
  treenimph.nimble
  src/
    treenimph.nim
    treenimph/
      model.nim
      diagnostics.nim
      validate.nim
      render_js.nim
      render_package.nim
      exporter.nim
      helpers.nim
  tests/
    test_model.nim
    test_diagnostics.nim
    test_validate.nim
    test_render_js.nim
    test_render_package.nim
    test_export.nim
    test_helpers.nim
    test_examples.nim
    snapshots/
      json_like_grammar.js
      expression_lang_grammar.js
  examples/
    arithmetic.nim
    json_like.nim
    simple_lang.nim
```

### 1.2 Nimble File

```nim
# treenimph.nimble
version       = "0.1.0"
author        = "TreeNimph Contributors"
description   = "A Nim library for authoring Tree-sitter grammars as composable typed objects"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"
```

Key decisions:
- `srcDir = "src"` — standard Nim convention. Users import as `import treenimph`.
- Minimum Nim 2.0.0 — ensures stable `ref object` variant semantics and modern features.
- No external dependencies for the core library. The only external tool is `tree-sitter` CLI, invoked optionally at export time.

### 1.3 Test Configuration

All test files use Nim's `unittest` module. Run tests with:

```bash
nimble test
# or individually:
nim r tests/test_model.nim
```

Add a test task to the nimble file:

```nim
task test, "Run all tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      exec "nim r " & f
```

---

## 2. Phase 1: Core Model

**File:** `src/treenimph/model.nim`
**Depends on:** nothing
**Spec sections:** §1 (Types), §2 (Constructors), §3 (Accessors)

This is the foundation. Every other module depends on it. Get it right and stable before moving on.

### 2.1 Imports

```nim
import std/options
```

Only `options` is needed (for `Option[string]` in `Grammar` and `QueryFiles`). No other standard library dependencies.

### 2.2 Type Definitions

Implement types in this exact order (forward references require it):

#### Step 1: Enums first

```nim
type
  ExprKind* = enum
    ekRef
    ekText
    ekRegex
    ekBlank
    ekSequence
    ekChoice
    ekOptional
    ekZeroOrMore
    ekOneOrMore
    ekField
    ekAlias
    ekToken
    ekImmediateToken
    ekPrecedence

  Assoc* = enum
    assocNone
    assocLeft
    assocRight
    assocDynamic

  DiagnosticKind* = enum
    dkError
    dkWarning
```

Note: `DiagnosticKind` is defined here in `model.nim` rather than `diagnostics.nim` to avoid a circular dependency situation. Alternatively, it can live in `diagnostics.nim` since `model.nim` does not depend on it. **Decision: keep `DiagnosticKind` in `diagnostics.nim`** — it is not needed by `model.nim`. Only `validate.nim` and `diagnostics.nim` use it.

#### Step 2: Expr variant type

```nim
type
  Expr* = ref object
    case kind*: ExprKind
    of ekRef:
      refName*: string
    of ekText:
      textValue*: string
    of ekRegex:
      regexPattern*: string
    of ekBlank:
      discard
    of ekSequence, ekChoice:
      items*: seq[Expr]
    of ekOptional, ekZeroOrMore, ekOneOrMore:
      item*: Expr
    of ekToken, ekImmediateToken:
      tokenExpr*: Expr
    of ekField:
      fieldName*: string
      fieldExpr*: Expr
    of ekAlias:
      aliasName*: string
      aliasExpr*: Expr
      aliasNamed*: bool
    of ekPrecedence:
      precLevel*: int
      precAssoc*: Assoc
      precExpr*: Expr
```

Implementation notes:
- `ref object` (not `object`) — required for recursive self-referential fields. A `Sequence` contains `seq[Expr]`, and each `Expr` can itself be a `Sequence`.
- `ekSequence` and `ekChoice` share the `items` field — this is valid because they are in the same `of` branch. This means you **cannot** distinguish them by field alone; you must check `e.kind`.
- `ekOptional`, `ekZeroOrMore`, `ekOneOrMore` share the `item` field — same pattern.
- `ekToken` and `ekImmediateToken` share `tokenExpr` — same pattern.
- Field names are intentionally prefixed (`refName`, `textValue`, `fieldName`, etc.) because Nim requires unique field names across variant branches. This is an internal detail hidden by constructor procs.

#### Step 3: Rule, Grammar, supporting types

```nim
type
  Rule* = object
    name*: string
    body*: Expr
    hidden*: bool

  QueryFiles* = object
    highlights*: Option[string]
    locals*: Option[string]
    injections*: Option[string]
    tags*: Option[string]

  Grammar* = object
    name*: string
    rules*: seq[Rule]
    word*: Option[string]
    extras*: seq[Expr]
    conflicts*: seq[seq[string]]
    supertypes*: seq[string]
    inline*: seq[string]
    externals*: seq[Expr]
    queryFiles*: Option[QueryFiles]
    scannerPath*: Option[string]

  ExportConfig* = object
    outDir*: string
    runGenerate*: bool
    writeQueryStubs*: bool
    overwrite*: bool
```

Implementation notes:
- `Rule` is a value type (`object`, not `ref object`). Rules are small, not recursive, and stored in `seq[Rule]`. Value semantics are simpler here.
- `Grammar` is also a value type. It holds `seq[Rule]` and `seq[Expr]`, where the `Expr` values are `ref` — so copying a `Grammar` is cheap (it copies seq headers and ref pointers, not deep expression trees).
- `ExportConfig` is a value type with sensible defaults: `runGenerate = false`, `writeQueryStubs = true`, `overwrite = true`. These defaults are set in the constructor proc, not in the type definition (Nim `object` fields default to zero/false/empty).

### 2.3 Constructor Procs

Every constructor is a `proc` that returns the appropriate type. Users never write `Expr(kind: ...)` directly.

#### Expression Constructors

```nim
proc Ref*(name: string): Expr =
  Expr(kind: ekRef, refName: name)

proc Text*(value: string): Expr =
  Expr(kind: ekText, textValue: value)

proc Regex*(pattern: string): Expr =
  Expr(kind: ekRegex, regexPattern: pattern)

proc Blank*(): Expr =
  Expr(kind: ekBlank)

proc Sequence*(items: varargs[Expr]): Expr =
  Expr(kind: ekSequence, items: @items)

proc Choice*(items: varargs[Expr]): Expr =
  Expr(kind: ekChoice, items: @items)

proc Optional*(item: Expr): Expr =
  Expr(kind: ekOptional, item: item)

proc ZeroOrMore*(item: Expr): Expr =
  Expr(kind: ekZeroOrMore, item: item)

proc OneOrMore*(item: Expr): Expr =
  Expr(kind: ekOneOrMore, item: item)

proc Field*(name: string, expr: Expr): Expr =
  Expr(kind: ekField, fieldName: name, fieldExpr: expr)

proc Alias*(name: string, expr: Expr, named = true): Expr =
  Expr(kind: ekAlias, aliasName: name, aliasExpr: expr, aliasNamed: named)

proc Token*(expr: Expr): Expr =
  Expr(kind: ekToken, tokenExpr: expr)

proc ImmediateToken*(expr: Expr): Expr =
  Expr(kind: ekImmediateToken, tokenExpr: expr)

proc Prec*(level: int, expr: Expr, assoc = assocNone): Expr =
  Expr(kind: ekPrecedence, precLevel: level, precAssoc: assoc, precExpr: expr)

proc PrecLeft*(level: int, expr: Expr): Expr =
  Prec(level, expr, assocLeft)

proc PrecRight*(level: int, expr: Expr): Expr =
  Prec(level, expr, assocRight)

proc PrecDynamic*(level: int, expr: Expr): Expr =
  Prec(level, expr, assocDynamic)
```

Implementation notes:
- `varargs[Expr]` in `Sequence` and `Choice` enables `Sequence(a, b, c)` syntax. The `@items` converts varargs to `seq[Expr]`.
- Constructors do **no** validation. They allow empty sequences, nil items, empty names, etc. Validation is a separate phase (§4). This keeps constructors simple and composable — partial expression trees can be built incrementally.
- `PrecLeft`, `PrecRight`, `PrecDynamic` are thin wrappers around `Prec`. They exist purely for ergonomics.
- Constructor names are capitalized (`Ref`, `Text`, `Field`) to visually distinguish them from Nim keywords and standard library procs. This is a deliberate API design choice.

**Potential pitfall:** Nim's `Ref` might shadow something — it does not. `ref` (lowercase) is a keyword, but `Ref` (capitalized) is a valid proc name.

#### Rule Constructor

```nim
proc Rule*(name: string, body: Expr, hidden = false): Rule =
  var h = hidden
  if name.len > 0 and name[0] == '_':
    h = true
  Rule(name: name, body: body, hidden: h)
```

Implementation notes:
- If the name starts with `_`, `hidden` is forced to `true` regardless of the passed value. This is the "underscore convention" from Tree-sitter.
- The check `name.len > 0` guards against empty name crash. Empty names are allowed at construction (caught by validation).
- If `hidden = true` and name does **not** start with `_`, the Rule stores the name as-is (e.g., `"foo"`). The renderer is responsible for prepending `_` when generating `grammar.js`. The validator computes the canonical name for ref resolution.

#### Grammar Constructor

```nim
proc Grammar*(
  name: string,
  rules: varargs[Rule],
  word = none(string),
  extras: openArray[Expr] = [],
  conflicts: openArray[seq[string]] = [],
  supertypes: openArray[string] = [],
  inline: openArray[string] = [],
  externals: openArray[Expr] = [],
  queryFiles = none(QueryFiles),
  scannerPath = none(string),
): Grammar =
  Grammar(
    name: name,
    rules: @rules,
    word: word,
    extras: @extras,
    conflicts: @conflicts,
    supertypes: @supertypes,
    inline: @inline,
    externals: @externals,
    queryFiles: queryFiles,
    scannerPath: scannerPath,
  )
```

Implementation notes:
- `rules` uses `varargs[Rule]` so users can write `Grammar(name = "foo", rules = [rule1, rule2])` or pass rules as separate arguments.
- All `openArray` parameters are converted to `seq` with `@`. This is standard Nim idiom.
- Default values: `word = none(string)`, `extras = []`, etc. This means the minimal Grammar is `Grammar(name = "foo", Rule("bar", Blank()))`.

#### ExportConfig Constructor

```nim
proc ExportConfig*(
  outDir: string,
  runGenerate = false,
  writeQueryStubs = true,
  overwrite = true,
): ExportConfig =
  ExportConfig(
    outDir: outDir,
    runGenerate: runGenerate,
    writeQueryStubs: writeQueryStubs,
    overwrite: overwrite,
  )
```

### 2.4 Accessor Procs

These are internal convenience procs. They are public (`*`) but primarily used by the library's own validator, renderer, and utility code.

```nim
proc inner*(e: Expr): Expr =
  ## Returns the single child expression for wrapper types.
  ## Raises FieldDefect for leaf or multi-child types.
  case e.kind
  of ekOptional, ekZeroOrMore, ekOneOrMore:
    e.item
  of ekToken, ekImmediateToken:
    e.tokenExpr
  of ekField:
    e.fieldExpr
  of ekAlias:
    e.aliasExpr
  of ekPrecedence:
    e.precExpr
  of ekRef, ekText, ekRegex, ekBlank, ekSequence, ekChoice:
    raise newException(FieldDefect,
      "expression kind " & $e.kind & " has no inner expression")

proc children*(e: Expr): seq[Expr] =
  ## Returns all direct child expressions.
  case e.kind
  of ekRef, ekText, ekRegex, ekBlank:
    @[]
  of ekSequence, ekChoice:
    e.items
  of ekOptional, ekZeroOrMore, ekOneOrMore:
    @[e.item]
  of ekToken, ekImmediateToken:
    @[e.tokenExpr]
  of ekField:
    @[e.fieldExpr]
  of ekAlias:
    @[e.aliasExpr]
  of ekPrecedence:
    @[e.precExpr]
```

Implementation notes:
- `inner` is a partial function — it raises on invalid kinds. This is acceptable because it is used in contexts where the caller has already checked `e.kind` or is grouping wrapper types together.
- `children` is a total function — it returns `@[]` for leaf nodes. This is useful for generic tree traversal.
- Both use exhaustive `case` matching — the compiler will error if a new `ExprKind` variant is added without updating these procs.

### 2.5 Canonical Name Helper

This is used by both validation and rendering, so define it in `model.nim`:

```nim
proc canonicalName*(r: Rule): string =
  ## Returns the canonical name for a rule.
  ## If hidden and name does not start with '_', prepends '_'.
  if r.hidden and r.name.len > 0 and r.name[0] != '_':
    "_" & r.name
  else:
    r.name
```

### 2.6 Testing Phase 1

Write `tests/test_model.nim` covering all constructor and accessor tests from Spec §14.1 before proceeding to Phase 2. This validates the foundation.

Key test patterns:

```nim
import unittest
import treenimph/model

suite "Expression Constructors":
  test "Ref basic":
    let e = Ref("identifier")
    check e.kind == ekRef
    check e.refName == "identifier"

  test "Sequence varargs":
    let e = Sequence(Text("a"), Text("b"), Text("c"))
    check e.kind == ekSequence
    check e.items.len == 3

  # ... etc for every constructor
```

**Gate:** All model tests must pass before moving to Phase 2.

---

## 3. Phase 2: Diagnostics

**File:** `src/treenimph/diagnostics.nim`
**Depends on:** nothing (leaf module)
**Spec sections:** §1.8, §1.9, §4.3, §4.5, §15

### 3.1 Type Definitions

```nim
import std/options

type
  DiagnosticKind* = enum
    dkError
    dkWarning

  Diagnostic* = object
    kind*: DiagnosticKind
    message*: string
    ruleName*: Option[string]
    hint*: Option[string]
```

### 3.2 Diagnostic Formatting

```nim
proc `$`*(d: Diagnostic): string =
  let prefix = case d.kind
    of dkError: "Error"
    of dkWarning: "Warning"
  result = prefix & ": " & d.message
  if d.ruleName.isSome:
    result.add "\n  In rule \"" & d.ruleName.get & "\""
  if d.hint.isSome:
    result.add "\n  Hint: " & d.hint.get
```

Implementation note: The format is `Error: <message>` on the first line, then optional indented lines for rule name and hint. This matches the spec exactly.

### 3.3 Diagnostic Constructor Helpers

These reduce boilerplate in the validator:

```nim
proc error*(message: string, ruleName = none(string), hint = none(string)): Diagnostic =
  Diagnostic(kind: dkError, message: message, ruleName: ruleName, hint: hint)

proc warning*(message: string, ruleName = none(string), hint = none(string)): Diagnostic =
  Diagnostic(kind: dkWarning, message: message, ruleName: ruleName, hint: hint)
```

### 3.4 Levenshtein Distance

```nim
proc levenshteinDistance*(a, b: string): int =
  ## Standard dynamic programming Levenshtein distance.
  ## Case-sensitive comparison.
  let
    m = a.len
    n = b.len

  # Edge cases
  if m == 0: return n
  if n == 0: return m

  # DP table: (m+1) x (n+1)
  var dp = newSeq[seq[int]](m + 1)
  for i in 0..m:
    dp[i] = newSeq[int](n + 1)
    dp[i][0] = i
  for j in 0..n:
    dp[0][j] = j

  for i in 1..m:
    for j in 1..n:
      let cost = if a[i-1] == b[j-1]: 0 else: 1
      dp[i][j] = min(
        dp[i-1][j] + 1,       # deletion
        min(
          dp[i][j-1] + 1,     # insertion
          dp[i-1][j-1] + cost  # substitution
        )
      )
  dp[m][n]
```

Implementation note: This is the standard O(m*n) DP algorithm. For TreeNimph's use case (comparing short identifiers), performance is not a concern. An optimized two-row version is possible but unnecessary.

**Optimization opportunity (not required for v1):** Use a two-row DP array to reduce memory from O(m*n) to O(min(m,n)). Not worth the complexity for v1.

### 3.5 Closest Match Finder

```nim
proc findClosestMatch*(target: string, candidates: seq[string], maxDistance = 2): Option[string] =
  ## Returns the candidate with the smallest Levenshtein distance to target,
  ## if that distance is <= maxDistance. On ties, returns the first match in seq order.
  var bestDist = maxDistance + 1
  var bestMatch = ""
  for c in candidates:
    let d = levenshteinDistance(target, c)
    if d < bestDist:
      bestDist = d
      bestMatch = c
  if bestDist <= maxDistance:
    some(bestMatch)
  else:
    none(string)
```

### 3.6 Error Types

```nim
type
  ValidationError* = object of CatchableError
    diagnostics*: seq[Diagnostic]

  ExportError* = object of CatchableError
```

Implementation note: `ValidationError` carries the full list of diagnostics so callers can inspect structured errors, not just the formatted message string.

To construct a `ValidationError` with both a message and diagnostics:

```nim
proc newValidationError*(diagnostics: seq[Diagnostic]): ref ValidationError =
  var msg = ""
  for d in diagnostics:
    if msg.len > 0:
      msg.add "\n\n"
    msg.add $d
  result = newException(ValidationError, msg)
  result.diagnostics = diagnostics
```

### 3.7 Testing Phase 2

Write `tests/test_diagnostics.nim` covering Spec §14.7 tests before proceeding.

**Gate:** All diagnostics tests must pass before moving to Phase 3.

---

## 4. Phase 3: Validation

**File:** `src/treenimph/validate.nim`
**Depends on:** `model`, `diagnostics`
**Spec sections:** §4 (all subsections)

### 4.1 Imports

```nim
import std/[options, sets, strutils, re]
import ./model
import ./diagnostics
```

Note: `re` is used for identifier validation (`=~`). Alternatively, use manual character checking to avoid the regex dependency:

```nim
proc isValidIdentifier(s: string): bool =
  if s.len == 0: return false
  if s[0] notin {'a'..'z', 'A'..'Z', '_'}: return false
  for i in 1..<s.len:
    if s[i] notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}: return false
  true
```

**Decision: Use manual character checking.** It avoids the `re` dependency and is clearer for this simple pattern. Define this as a private helper.

### 4.2 Validation Architecture

The validator follows a specific traversal order (Spec §4.4):

1. Grammar-level checks (V01, V02, V03)
2. Rule-level checks — for each rule in order (V04, V05, V06, V07, V08)
3. Expression tree checks — for each rule body, depth-first pre-order (V09, V10, V11, V12, V13, V14, V15, V16)
4. Grammar config checks (V17, V18, V19, V20, V21, V22, V23)

All diagnostics are collected. No short-circuiting.

### 4.3 Implementation Structure

```nim
proc validate*(g: Grammar): seq[Diagnostic] =
  var diags: seq[Diagnostic] = @[]

  # --- Phase 1: Grammar-level checks ---
  validateGrammarLevel(g, diags)

  # --- Phase 2: Build rule name set ---
  var ruleNames: HashSet[string]
  var ruleNameList: seq[string]  # ordered, for "did you mean"
  var rulePositions: Table[string, int]  # canonical name -> 1-indexed position
  buildRuleNameSet(g, ruleNames, ruleNameList, rulePositions, diags)

  # --- Phase 3: Expression tree checks ---
  var externalNames: HashSet[string]
  collectExternalRefs(g.externals, externalNames)
  let validRefs = ruleNames + externalNames

  for i, rule in g.rules:
    if rule.body != nil:
      validateExprTree(rule.body, rule.canonicalName, validRefs, ruleNameList, diags)

  # --- Phase 4: Grammar config checks ---
  validateGrammarConfig(g, ruleNames, ruleNameList, diags)

  diags
```

### 4.4 Grammar-Level Checks (V01–V03)

```nim
proc validateGrammarLevel(g: Grammar, diags: var seq[Diagnostic]) =
  # V01: Grammar name must be non-empty
  if g.name.len == 0:
    diags.add error("Grammar name must not be empty")

  # V02: Grammar name must be a valid identifier
  elif not isValidIdentifier(g.name):
    diags.add error("Grammar name \"" & g.name & "\" is not a valid identifier")

  # V03: Grammar must have at least one rule
  if g.rules.len == 0:
    diags.add error("Grammar must define at least one rule")
```

Note: V01 and V02 are mutually exclusive (if name is empty, don't also check identifier validity). V03 is independent.

### 4.5 Rule-Level Checks (V04–V08)

```nim
proc buildRuleNameSet(g: Grammar, ruleNames: var HashSet[string],
                      ruleNameList: var seq[string],
                      rulePositions: var Table[string, int],
                      diags: var seq[Diagnostic]) =
  for i, rule in g.rules:
    let pos = i + 1  # 1-indexed

    # V05: Rule name must be non-empty
    if rule.name.len == 0:
      diags.add error("Rule name must not be empty",
                       hint = some("Rule #" & $pos))
      continue

    let cname = rule.canonicalName

    # V06: Rule name must be a valid identifier
    # Pattern: ^_?[a-zA-Z_][a-zA-Z0-9_]*$
    # The canonical name may start with _ (hidden prefix), then must be a valid identifier
    if not isValidRuleName(cname):
      diags.add error("Rule name \"" & cname & "\" is not a valid identifier",
                       ruleName = some(cname))

    # V07: Rule name must not start with MISSING or UNEXPECTED
    if cname.startsWith("MISSING") or cname.startsWith("UNEXPECTED") or
       (cname.len > 1 and cname[0] == '_' and
        (cname[1..^1].startsWith("MISSING") or cname[1..^1].startsWith("UNEXPECTED"))):
      diags.add error("Rule name \"" & cname & "\" uses a reserved prefix",
                       ruleName = some(cname),
                       hint = some("Tree-sitter reserves names starting with \"MISSING\" and \"UNEXPECTED\""))

    # V04: Duplicate rule names
    if cname in ruleNames:
      let firstPos = rulePositions[cname]
      diags.add error("Duplicate rule name \"" & cname & "\"",
                       ruleName = some(cname),
                       hint = some("First defined as rule #" & $firstPos & ", redefined as rule #" & $pos))
    else:
      ruleNames.incl cname
      ruleNameList.add cname
      rulePositions[cname] = pos

    # V08: Rule body must not be nil
    if rule.body == nil:
      diags.add error("Rule \"" & cname & "\" has a nil body",
                       ruleName = some(cname))
```

Implementation notes:
- `isValidRuleName` should accept the pattern `^_?[a-zA-Z_][a-zA-Z0-9_]*$`. This is slightly different from `isValidIdentifier` because the canonical name may have a leading `_` followed by a valid identifier:

```nim
proc isValidRuleName(s: string): bool =
  ## Validates: ^_?[a-zA-Z_][a-zA-Z0-9_]*$
  if s.len == 0: return false
  var start = 0
  if s[0] == '_':
    start = 1
    if start >= s.len: return false
  if s[start] notin {'a'..'z', 'A'..'Z', '_'}: return false
  for i in (start+1)..<s.len:
    if s[i] notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}: return false
  true
```

- V07 checks need to handle both `MISSING_foo` and `_MISSING_foo` (hidden rule with MISSING prefix). The spec says the canonical name is checked, so check after `_` prefix if present.

### 4.6 Expression Tree Checks (V09–V16)

The expression tree is traversed depth-first, pre-order. Each node is checked, then its children are recursively traversed.

```nim
proc validateExprTree(e: Expr, ruleName: string,
                      validRefs: HashSet[string],
                      ruleNameList: seq[string],
                      diags: var seq[Diagnostic]) =
  if e == nil:
    return  # nil children are caught by parent checks

  case e.kind
  of ekRef:
    # V09: Undefined Ref target
    if e.refName notin validRefs:
      var d = error("Unknown rule reference \"" & e.refName & "\" in rule \"" & ruleName & "\"",
                     ruleName = some(ruleName))
      let suggestion = findClosestMatch(e.refName, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

  of ekSequence:
    # V10: Empty Sequence
    if e.items.len == 0:
      diags.add error("Sequence must contain at least one item",
                       ruleName = some(ruleName),
                       hint = some("In rule \"" & ruleName & "\""))
    # V16: Nil items in Sequence
    for i, item in e.items:
      if item == nil:
        diags.add error("Sequence contains a nil item at position " & $(i+1) & " in rule \"" & ruleName & "\"",
                         ruleName = some(ruleName))

  of ekChoice:
    # V11: Empty Choice
    if e.items.len == 0:
      diags.add error("Choice must contain at least one item",
                       ruleName = some(ruleName),
                       hint = some("In rule \"" & ruleName & "\""))
    # V16: Nil items in Choice
    for i, item in e.items:
      if item == nil:
        diags.add error("Choice contains a nil item at position " & $(i+1) & " in rule \"" & ruleName & "\"",
                         ruleName = some(ruleName))

  of ekField:
    # V12: Invalid field name
    if not isValidIdentifier(e.fieldName):
      diags.add error("Invalid field name \"" & e.fieldName & "\" in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))
    # V15: Nil child
    if e.fieldExpr == nil:
      diags.add error("Field has a nil child expression in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))

  of ekAlias:
    # V14: Empty alias name
    if e.aliasName.len == 0:
      diags.add error("Alias name must not be empty in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))
    # V13: Invalid alias name (only for named aliases)
    elif e.aliasNamed and not isValidRuleName(e.aliasName):
      diags.add error("Invalid alias name \"" & e.aliasName & "\" in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName),
                       hint = some("Named aliases must be valid identifiers"))
    # V15: Nil child
    if e.aliasExpr == nil:
      diags.add error("Alias has a nil child expression in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))

  of ekOptional:
    if e.item == nil:
      diags.add error("Optional has a nil child expression in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))

  of ekZeroOrMore:
    if e.item == nil:
      diags.add error("ZeroOrMore has a nil child expression in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))

  of ekOneOrMore:
    if e.item == nil:
      diags.add error("OneOrMore has a nil child expression in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))

  of ekToken:
    if e.tokenExpr == nil:
      diags.add error("Token has a nil child expression in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))

  of ekImmediateToken:
    if e.tokenExpr == nil:
      diags.add error("ImmediateToken has a nil child expression in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))

  of ekPrecedence:
    if e.precExpr == nil:
      diags.add error("Prec has a nil child expression in rule \"" & ruleName & "\"",
                       ruleName = some(ruleName))

  of ekText, ekRegex, ekBlank:
    discard  # leaf nodes, no structural checks

  # Recurse into children
  for child in e.children:
    if child != nil:
      validateExprTree(child, ruleName, validRefs, ruleNameList, diags)
```

Implementation notes:
- The `case e.kind` is exhaustive — the compiler will catch missing variants.
- Children are recursed into after the node's own checks. This is depth-first pre-order.
- Nil children are checked at the parent level (V15, V16) but skipped during recursion to avoid nil dereference.

### 4.7 Grammar Config Checks (V17–V23)

```nim
proc validateGrammarConfig(g: Grammar, ruleNames: HashSet[string],
                           ruleNameList: seq[string],
                           diags: var seq[Diagnostic]) =
  # V17: Word rule does not exist
  if g.word.isSome:
    let w = g.word.get
    if w notin ruleNames:
      var d = error("Word rule \"" & w & "\" does not exist")
      let suggestion = findClosestMatch(w, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

  # V18: Invalid extras reference
  for expr in g.extras:
    if expr != nil and expr.kind == ekRef:
      if expr.refName notin ruleNames:
        var d = error("Extras reference \"" & expr.refName & "\" does not match any rule")
        let suggestion = findClosestMatch(expr.refName, ruleNameList)
        if suggestion.isSome:
          d.hint = some("Did you mean \"" & suggestion.get & "\"?")
        diags.add d

  # V19: Invalid conflicts reference
  for conflict in g.conflicts:
    # V22: Empty conflicts entry
    if conflict.len < 2:
      diags.add error("Conflict entry must contain at least 2 rule names")
    for name in conflict:
      if name notin ruleNames:
        var d = error("Conflict reference \"" & name & "\" does not match any rule")
        let suggestion = findClosestMatch(name, ruleNameList)
        if suggestion.isSome:
          d.hint = some("Did you mean \"" & suggestion.get & "\"?")
        diags.add d

  # V20: Invalid supertypes reference
  for name in g.supertypes:
    if name notin ruleNames:
      var d = error("Supertype \"" & name & "\" does not match any rule")
      let suggestion = findClosestMatch(name, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

  # V21: Invalid inline reference
  for name in g.inline:
    if name notin ruleNames:
      var d = error("Inline rule \"" & name & "\" does not match any rule")
      let suggestion = findClosestMatch(name, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

  # V23: Scanner file does not exist
  if g.scannerPath.isSome:
    let path = g.scannerPath.get
    if not fileExists(path):
      diags.add error("Scanner file \"" & path & "\" does not exist")
```

### 4.8 External Ref Collection

```nim
proc collectExternalRefs(externals: seq[Expr], names: var HashSet[string]) =
  for e in externals:
    if e != nil and e.kind == ekRef:
      names.incl e.refName
```

This walks `grammar.externals` and collects all `Ref` names. These are added to the valid reference set so that rules can reference externals without triggering V09.

### 4.9 Convenience Procs

```nim
proc validateOrRaise*(g: Grammar) =
  let diags = g.validate()
  var errors: seq[Diagnostic] = @[]
  for d in diags:
    if d.kind == dkError:
      errors.add d
  if errors.len > 0:
    raise newValidationError(errors)
```

### 4.10 Testing Phase 3

Write `tests/test_validate.nim` covering all V01–V23 test cases from Spec §14.2.

**Key test pattern:**

```nim
test "V09 undefined ref":
  let g = Grammar("test",
    Rule("source", Ref("nonexistent"))
  )
  let diags = g.validate()
  check diags.len >= 1
  check diags.anyIt(it.message.contains("Unknown rule reference"))
```

**Gate:** All validation tests must pass before moving to Phase 4.

---

## 5. Phase 4: JS Rendering

**File:** `src/treenimph/render_js.nim`
**Depends on:** `model`
**Spec sections:** §5 (all subsections)

This is the largest and most intricate module. The renderer must produce deterministic, readable, correctly-formatted JavaScript.

### 5.1 Imports

```nim
import std/[strutils, sequtils, options]
import ./model
```

### 5.2 Architecture

The renderer is built from these components:

1. **`renderExpr(e: Expr, indent: int): string`** — recursive expression renderer
2. **`renderSection(...)` helpers** — for each grammar section (word, extras, conflicts, etc.)
3. **`renderGrammarJs(g: Grammar): string`** — top-level entry point

### 5.3 String Escaping Helpers

```nim
proc escapeJsSingleQuote(s: string): string =
  ## Escapes a string for use in a single-quoted JS string literal.
  result = ""
  for c in s:
    case c
    of '\\': result.add "\\\\"
    of '\'': result.add "\\'"
    of '\n': result.add "\\n"
    of '\r': result.add "\\r"
    of '\t': result.add "\\t"
    else: result.add c

proc escapeRegexSlash(pattern: string): string =
  ## Escapes unescaped forward slashes in a regex pattern.
  result = ""
  var i = 0
  while i < pattern.len:
    if pattern[i] == '\\' and i + 1 < pattern.len:
      # Escaped character — pass through both chars
      result.add pattern[i]
      result.add pattern[i + 1]
      i += 2
    elif pattern[i] == '/':
      result.add "\\/"
      i += 1
    else:
      result.add pattern[i]
      i += 1
```

Implementation notes:
- `escapeJsSingleQuote` handles the four special characters plus `\` itself. All other characters pass through verbatim.
- `escapeRegexSlash` only escapes unescaped `/` — it must not double-escape `\/` that the user already escaped. The implementation tracks backslash-escaped sequences to distinguish.

### 5.4 Indentation Helper

```nim
proc indent(level: int): string =
  repeat(' ', level * 2)
```

All indentation is 2 spaces. No tabs.

### 5.5 Expression Renderer

This is the core of the renderer. It handles single-line vs. multi-line formatting based on the 80-character heuristic.

```nim
proc renderExpr(e: Expr, indentLevel: int): string =
  ## Renders an expression to JavaScript source.
  ## indentLevel is the current nesting depth for multi-line formatting.
  case e.kind
  of ekRef:
    "$." & e.refName

  of ekText:
    "'" & escapeJsSingleQuote(e.textValue) & "'"

  of ekRegex:
    "/" & escapeRegexSlash(e.regexPattern) & "/"

  of ekBlank:
    "blank()"

  of ekSequence:
    renderCallExpr("seq", e.items, indentLevel)

  of ekChoice:
    renderCallExpr("choice", e.items, indentLevel)

  of ekOptional:
    renderWrapExpr("optional", e.item, indentLevel)

  of ekZeroOrMore:
    renderWrapExpr("repeat", e.item, indentLevel)

  of ekOneOrMore:
    renderWrapExpr("repeat1", e.item, indentLevel)

  of ekField:
    renderFieldExpr(e, indentLevel)

  of ekAlias:
    renderAliasExpr(e, indentLevel)

  of ekToken:
    renderWrapExpr("token", e.tokenExpr, indentLevel)

  of ekImmediateToken:
    renderWrapExpr("token.immediate", e.tokenExpr, indentLevel)

  of ekPrecedence:
    renderPrecExpr(e, indentLevel)
```

### 5.6 Call Expression Renderer (seq, choice)

```nim
proc renderCallExpr(funcName: string, items: seq[Expr], indentLevel: int): string =
  ## Renders seq(...) or choice(...) with single-line/multi-line heuristic.
  let renderedItems = items.mapIt(renderExpr(it, indentLevel + 1))

  # Try single-line first
  let singleLine = funcName & "(" & renderedItems.join(", ") & ")"
  let currentIndent = indent(indentLevel).len
  if renderedItems.allIt(not it.contains('\n')) and
     currentIndent + singleLine.len <= 80:
    return singleLine

  # Multi-line
  let innerIndent = indent(indentLevel + 1)
  result = funcName & "(\n"
  for item in renderedItems:
    # If the item itself is multi-line, indent each line
    let indented = item.split('\n').mapIt(innerIndent & it).join("\n")
    # Actually: first line already has innerIndent from the mapIt
    # Simpler approach: prepend indent, append comma
    result.add innerIndent & item & ",\n"
  result.add indent(indentLevel) & ")"
```

**Important detail on multi-line indentation:** When a child expression is itself multi-line (e.g., a nested `seq(...)` that spans multiple lines), each line of that child needs proper indentation. The approach above is simplified — for the full implementation:

```nim
proc indentMultiline(s: string, level: int): string =
  ## Indents all lines of a multi-line string.
  ## The first line is NOT indented (caller handles it).
  let lines = s.split('\n')
  if lines.len <= 1:
    return s
  let ind = indent(level)
  result = lines[0]
  for i in 1..<lines.len:
    result.add "\n" & ind & lines[i]
```

Then in `renderCallExpr`:

```nim
for item in renderedItems:
  result.add innerIndent & indentMultiline(item, indentLevel + 1) & ",\n"
```

### 5.7 Wrapper Expression Renderer (optional, repeat, token, etc.)

```nim
proc renderWrapExpr(funcName: string, child: Expr, indentLevel: int): string =
  ## Renders optional(...), repeat(...), token(...), etc.
  let rendered = renderExpr(child, indentLevel + 1)
  let singleLine = funcName & "(" & rendered & ")"
  let currentIndent = indent(indentLevel).len

  if not rendered.contains('\n') and currentIndent + singleLine.len <= 80:
    return singleLine

  # Multi-line
  let innerIndent = indent(indentLevel + 1)
  result = funcName & "(\n"
  result.add innerIndent & indentMultiline(rendered, indentLevel + 1) & ",\n"
  result.add indent(indentLevel) & ")"
```

### 5.8 Field Expression Renderer

```nim
proc renderFieldExpr(e: Expr, indentLevel: int): string =
  let childRendered = renderExpr(e.fieldExpr, indentLevel + 1)
  let singleLine = "field('" & e.fieldName & "', " & childRendered & ")"
  let currentIndent = indent(indentLevel).len

  if not childRendered.contains('\n') and currentIndent + singleLine.len <= 80:
    return singleLine

  # Multi-line: field('name', <complex expr>)
  # The opening is on the same line, child continues
  result = "field('" & e.fieldName & "', " & indentMultiline(childRendered, indentLevel + 1) & ")"
```

### 5.9 Alias Expression Renderer

```nim
proc renderAliasExpr(e: Expr, indentLevel: int): string =
  let childRendered = renderExpr(e.aliasExpr, indentLevel + 1)
  let nameRendered = if e.aliasNamed:
    "$." & e.aliasName
  else:
    "'" & escapeJsSingleQuote(e.aliasName) & "'"

  "alias(" & childRendered & ", " & nameRendered & ")"
```

Note: The alias renders as `alias(<expr>, <name>)` — expression first, name second. This matches Tree-sitter's `alias()` argument order.

### 5.10 Precedence Expression Renderer

```nim
proc renderPrecExpr(e: Expr, indentLevel: int): string =
  let funcName = case e.precAssoc
    of assocNone: "prec"
    of assocLeft: "prec.left"
    of assocRight: "prec.right"
    of assocDynamic: "prec.dynamic"

  let childRendered = renderExpr(e.precExpr, indentLevel + 1)
  let singleLine = funcName & "(" & $e.precLevel & ", " & childRendered & ")"
  let currentIndent = indent(indentLevel).len

  if not childRendered.contains('\n') and currentIndent + singleLine.len <= 80:
    return singleLine

  # Multi-line
  result = funcName & "(" & $e.precLevel & ", " & indentMultiline(childRendered, indentLevel + 1) & ")"
```

### 5.11 Grammar-Level Renderer

```nim
proc renderGrammarJs*(g: Grammar): string =
  result = "// Generated by TreeNimph — do not edit manually.\n\n"
  result.add "module.exports = grammar({\n"
  result.add "  name: '" & g.name & "',\n"

  # Word section
  if g.word.isSome:
    result.add "\n  word: $ => $." & g.word.get & ",\n"

  # Extras section
  if g.extras.len > 0:
    result.add "\n  extras: $ => [\n"
    for e in g.extras:
      result.add "    " & renderExpr(e, 2) & ",\n"
    result.add "  ],\n"

  # Supertypes section
  if g.supertypes.len > 0:
    result.add "\n  supertypes: $ => [\n"
    for name in g.supertypes:
      result.add "    $." & name & ",\n"
    result.add "  ],\n"

  # Inline section
  if g.inline.len > 0:
    result.add "\n  inline: $ => [\n"
    for name in g.inline:
      result.add "    $." & name & ",\n"
    result.add "  ],\n"

  # Conflicts section
  if g.conflicts.len > 0:
    result.add "\n  conflicts: $ => [\n"
    for conflict in g.conflicts:
      result.add "    [" & conflict.mapIt("$." & it).join(", ") & "],\n"
    result.add "  ],\n"

  # Externals section
  if g.externals.len > 0:
    result.add "\n  externals: $ => [\n"
    for e in g.externals:
      result.add "    " & renderExpr(e, 2) & ",\n"
    result.add "  ],\n"

  # Rules section
  result.add "\n  rules: {\n"
  for i, rule in g.rules:
    let cname = rule.canonicalName
    let bodyRendered = renderExpr(rule.body, 2)

    if i > 0:
      result.add "\n"  # blank line between rules

    if not bodyRendered.contains('\n'):
      result.add "    " & cname & ": $ => " & bodyRendered & ",\n"
    else:
      result.add "    " & cname & ": $ => " & indentMultiline(bodyRendered, 2) & ",\n"

  result.add "  }\n"
  result.add "});\n"
```

Implementation notes:
- Sections are separated by blank lines (the `\n` before each section header).
- Empty sections are omitted entirely (not rendered at all).
- Rules are separated by blank lines (`\n` between rules, not before the first).
- Trailing commas on everything (Tree-sitter convention).
- The `$ =>` arrow is part of Tree-sitter's grammar DSL format — each rule and section is a function that receives `$` (the grammar's rule namespace).
- The indentation base for rule bodies is level 2 (8 spaces from the left: 4 for `rules: {` + 4 for the rule name).

**Determinism guarantee:** The renderer has no randomness, no timestamps, no system-dependent values. Same `Grammar` object always produces the same output string byte-for-byte.

### 5.12 Testing Phase 4

Write `tests/test_render_js.nim` covering all expression-level and grammar-level tests from Spec §14.3.

For snapshot tests, create expected output files in `tests/snapshots/` and compare:

```nim
test "snapshot json-like grammar":
  let g = buildJsonLikeGrammar()  # helper that constructs the grammar
  let output = g.renderGrammarJs()
  let expected = readFile("tests/snapshots/json_like_grammar.js")
  check output == expected
```

Create snapshot files by first running the renderer and manually verifying the output is correct, then saving it as the expected file.

**Gate:** All renderer tests must pass before moving to Phase 5.

---

## 6. Phase 5: Package Rendering

**File:** `src/treenimph/render_package.nim`
**Depends on:** `model`
**Spec sections:** §6 (package.json, tree-sitter.json)

### 6.1 Imports

```nim
import std/[json, options]
import ./model
```

Uses `std/json` for JSON generation. This ensures well-formed, properly escaped JSON output.

### 6.2 `package.json` Renderer

```nim
proc renderPackageJson*(g: Grammar): string =
  let j = %*{
    "name": "tree-sitter-" & g.name,
    "version": "0.1.0",
    "description": g.name & " grammar for tree-sitter",
    "main": "bindings/node",
    "types": "bindings/node",
    "keywords": [
      "incremental",
      "parsing",
      "tree-sitter",
      g.name
    ],
    "files": [
      "grammar.js",
      "tree-sitter.json",
      "binding.gyp",
      "prebuilds/**",
      "bindings/node/*",
      "queries/*",
      "src/**",
      "*.wasm"
    ],
    "dependencies": {
      "node-addon-api": "^8.2.2",
      "node-gyp-build": "^4.8.2"
    },
    "devDependencies": {
      "tree-sitter-cli": "^0.25.0"
    },
    "peerDependencies": {
      "tree-sitter": "^0.22.0"
    },
    "peerDependenciesMeta": {
      "tree-sitter": {
        "optional": true
      }
    },
    "scripts": {
      "install": "node-gyp-build",
      "prestart": "tree-sitter build --wasm",
      "start": "tree-sitter playground",
      "test": "tree-sitter test"
    }
  }
  pretty(j, indent = 2) & "\n"
```

Implementation note: `std/json`'s `pretty` produces deterministic output. The trailing `\n` ensures the file ends with a newline (standard convention).

**Caveat:** `std/json`'s `%*` macro preserves key order in Nim 2.0+ with `OrderedTable`. Verify this produces the exact key order specified in the spec. If not, construct the `JsonNode` manually with `newJObject` and add keys in order.

### 6.3 `tree-sitter.json` Renderer

```nim
proc renderTreeSitterJson*(g: Grammar, queryFiles: Option[QueryFiles] = none(QueryFiles),
                           writeQueryStubs = true): string =
  var grammarEntry = %*{
    "name": g.name,
    "scope": "source." & g.name,
    "path": "."
  }

  # file-types is always an empty array in v1
  grammarEntry["file-types"] = newJArray()

  # Only include query paths for files that will actually be written
  let qf = if g.queryFiles.isSome: g.queryFiles.get else: QueryFiles()

  if qf.highlights.isSome or writeQueryStubs:
    grammarEntry["highlights"] = %"queries/highlights.scm"
  if qf.tags.isSome or writeQueryStubs:
    grammarEntry["tags"] = %"queries/tags.scm"
  if qf.locals.isSome or writeQueryStubs:
    grammarEntry["locals"] = %"queries/locals.scm"
  if qf.injections.isSome or writeQueryStubs:
    grammarEntry["injections"] = %"queries/injections.scm"

  let j = %*{
    "grammars": [grammarEntry],
    "metadata": {
      "version": "0.1.0",
      "description": g.name & " grammar for tree-sitter",
      "links": newJObject()
    },
    "bindings": {
      "c": true,
      "go": true,
      "node": true,
      "python": true,
      "rust": true,
      "swift": true
    }
  }
  pretty(j, indent = 2) & "\n"
```

### 6.4 Testing Phase 5

Write `tests/test_render_package.nim` covering Spec §14.4 tests.

**Gate:** All package rendering tests must pass before moving to Phase 6.

---

## 7. Phase 6: Helpers

**File:** `src/treenimph/helpers.nim`
**Depends on:** `model`
**Spec sections:** §10

### 7.1 Implementation

```nim
import ./model

proc delimitedList*(item: Expr, sep: Expr, trailing = false): Expr =
  ## Creates a pattern for one or more items separated by sep.
  if trailing:
    Sequence(item, ZeroOrMore(Sequence(sep, item)), Optional(sep))
  else:
    Sequence(item, ZeroOrMore(Sequence(sep, item)))

proc optionalDelimitedList*(item: Expr, sep: Expr, trailing = false): Expr =
  ## Like delimitedList, but the entire list is optional (zero items allowed).
  Optional(delimitedList(item, sep, trailing))

proc balanced*(open, close: string, content: Expr): Expr =
  ## Creates a pattern for balanced delimiters around content.
  Sequence(Text(open), content, Text(close))

proc keyword*(word: string): Expr =
  ## Semantic alias for Text — signals the string is a language keyword.
  Text(word)
```

Implementation notes:
- These are pure functions returning `Expr` values. No side effects.
- `delimitedList` produces `seq(item, repeat(seq(sep, item)))` — this is the standard pattern for one-or-more separated lists.
- `optionalDelimitedList` wraps in `Optional` for zero-or-more.
- `keyword` is intentionally trivial — it exists for semantic clarity in grammar definitions.

### 7.2 Testing Phase 6

Write `tests/test_helpers.nim` covering Spec §14.6 tests.

Verify both structure (correct `ExprKind` and nesting) and rendered output (renders to expected JS).

**Gate:** All helper tests must pass before moving to Phase 7.

---

## 8. Phase 7: Export

**File:** `src/treenimph/exporter.nim`
**Depends on:** `model`, `validate`, `render_js`, `render_package`, `diagnostics`
**Spec sections:** §7 (Query Files), §8 (Export)

This is the only module with side effects (file I/O, process execution).

### 8.1 Imports

```nim
import std/[os, osproc, options, strutils, json]
import ./model
import ./validate
import ./render_js
import ./render_package
import ./diagnostics
```

### 8.2 Constants

```nim
const
  TreeNimphJsHeader* = "// Generated by TreeNimph — do not edit manually."
  TreeNimphScmHeader* = "; Generated by TreeNimph — do not edit manually."
```

### 8.3 File Ownership Detection

```nim
proc isTreeNimphOwned(path: string, header: string): bool =
  ## Checks if a file is owned by TreeNimph by inspecting its first line.
  if not fileExists(path):
    return false
  let content = readFile(path)
  content.startsWith(header)

proc isTreeNimphPackageJson(path: string, grammarName: string): bool =
  ## Checks if a package.json is owned by TreeNimph.
  if not fileExists(path):
    return false
  try:
    let j = parseJson(readFile(path))
    j["name"].getStr() == "tree-sitter-" & grammarName
  except:
    false

proc isTreeNimphTreeSitterJson(path: string, grammarName: string): bool =
  ## Checks if a tree-sitter.json is owned by TreeNimph.
  if not fileExists(path):
    return false
  try:
    let j = parseJson(readFile(path))
    j["grammars"][0]["name"].getStr() == grammarName
  except:
    false
```

### 8.4 Safe Write Helper

```nim
proc safeWrite(path: string, content: string, canOverwrite: bool,
               ownershipCheck: proc(): bool) =
  ## Writes a file with ownership-aware overwrite protection.
  if fileExists(path):
    if not canOverwrite:
      raise newException(ExportError,
        "File already exists and overwrite is disabled: " & path)
    if not ownershipCheck():
      raise newException(ExportError,
        "Refusing to overwrite file not generated by TreeNimph: " & path)
  writeFile(path, content)
```

### 8.5 Export Implementation

```nim
proc exportGrammar*(g: Grammar, config: ExportConfig) =
  ## Exports the grammar as a Tree-sitter package.
  ## Raises ValidationError if the grammar is invalid.
  ## Raises ExportError if file operations fail.

  # Step 1: Validate
  g.validateOrRaise()

  let outDir = config.outDir
  let queriesDir = outDir / "queries"
  let srcDir = outDir / "src"

  # Step 2: Create directory structure
  createDir(outDir)
  createDir(queriesDir)
  createDir(srcDir)

  # Step 3: Write grammar.js
  let grammarJsContent = g.renderGrammarJs()
  let grammarJsPath = outDir / "grammar.js"
  safeWrite(grammarJsPath, grammarJsContent, config.overwrite,
    proc(): bool = isTreeNimphOwned(grammarJsPath, TreeNimphJsHeader))

  # Step 4: Write package.json
  let packageJsonContent = g.renderPackageJson()
  let packageJsonPath = outDir / "package.json"
  safeWrite(packageJsonPath, packageJsonContent, config.overwrite,
    proc(): bool = isTreeNimphPackageJson(packageJsonPath, g.name))

  # Step 5: Write tree-sitter.json
  let writeStubs = config.writeQueryStubs
  let treeSitterJsonContent = g.renderTreeSitterJson(g.queryFiles, writeStubs)
  let treeSitterJsonPath = outDir / "tree-sitter.json"
  safeWrite(treeSitterJsonPath, treeSitterJsonContent, config.overwrite,
    proc(): bool = isTreeNimphTreeSitterJson(treeSitterJsonPath, g.name))

  # Step 6: Write query files
  let qf = if g.queryFiles.isSome: g.queryFiles.get else: QueryFiles()
  writeQueryFile(queriesDir / "highlights.scm", qf.highlights, writeStubs, config.overwrite)
  writeQueryFile(queriesDir / "locals.scm", qf.locals, writeStubs, config.overwrite)
  writeQueryFile(queriesDir / "injections.scm", qf.injections, writeStubs, config.overwrite)
  writeQueryFile(queriesDir / "tags.scm", qf.tags, writeStubs, config.overwrite)

  # Step 7: Copy scanner
  if g.scannerPath.isSome:
    let scannerSource = g.scannerPath.get
    let scannerDest = srcDir / "scanner.c"
    copyFile(scannerSource, scannerDest)

  # Step 8: Run tree-sitter generate
  if config.runGenerate:
    let (output, exitCode) = execCmdEx("tree-sitter generate", workingDir = outDir)
    if exitCode != 0:
      raise newException(ExportError,
        "tree-sitter generate failed (exit code " & $exitCode & "):\n" & output)
    let parserPath = srcDir / "parser.c"
    if not fileExists(parserPath):
      raise newException(ExportError,
        "tree-sitter generate succeeded but src/parser.c was not created")
```

### 8.6 Query File Writer

```nim
proc writeQueryFile(path: string, content: Option[string], writeStubs: bool, overwrite: bool) =
  if content.isSome:
    # Passthrough: write verbatim, always overwrite
    writeFile(path, content.get)
  elif writeStubs:
    # Stub: write header-only file, respect ownership
    if fileExists(path):
      if not overwrite:
        return  # don't overwrite in no-overwrite mode
      if not isTreeNimphOwned(path, TreeNimphScmHeader):
        return  # don't overwrite user-authored query files
    writeFile(path, TreeNimphScmHeader & "\n")
  # else: skip
```

### 8.7 Testing Phase 7

Write `tests/test_export.nim` covering Spec §14.5 tests. Use temporary directories:

```nim
import std/[tempfiles, os]

test "export creates directory structure":
  let tmpDir = createTempDir("treenimph_test_", "")
  defer: removeDir(tmpDir)

  let outDir = tmpDir / "output"
  let g = Grammar("test", Rule("source", Blank()))
  g.exportGrammar(ExportConfig(outDir = outDir))

  check dirExists(outDir)
  check dirExists(outDir / "queries")
  check dirExists(outDir / "src")
```

**Gate:** All export tests must pass before moving to Phase 8.

---

## 9. Phase 8: Public API

**File:** `src/treenimph.nim`
**Depends on:** all submodules
**Spec sections:** §13 (Public API Surface)

### 9.1 Implementation

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

export model
export diagnostics
export validate
export render_js
export render_package
export exporter
export helpers
```

This re-exports everything so users write `import treenimph` and get the full API.

### 9.2 Introspection: Summary

The `summary` proc can live in `model.nim` or in a separate small module. Since it depends only on `model`, it fits in `model.nim`:

```nim
proc summary*(g: Grammar): string =
  result = "Grammar: " & g.name & " (" & $g.rules.len & " rules)\n"

  result.add "Word: "
  if g.word.isSome:
    result.add g.word.get
  else:
    result.add "none"
  result.add "\n"

  result.add "Extras: " & $g.extras.len & " entries\n"
  result.add "Conflicts: " & $g.conflicts.len & " entries\n"

  result.add "Supertypes: "
  if g.supertypes.len > 0:
    result.add g.supertypes.join(", ")
  else:
    result.add "none"
  result.add "\n"

  result.add "Inline: "
  if g.inline.len > 0:
    result.add g.inline.join(", ")
  else:
    result.add "none"
  result.add "\n"

  result.add "Externals: " & $g.externals.len & " entries\n"

  result.add "Rules:\n"
  for rule in g.rules:
    result.add "  " & rule.canonicalName & "\n"
```

---

## 10. Phase 9: Testing

**Spec sections:** §14 (all subsections)

### 10.1 Test File Overview

| File | Module Tested | Spec Section | Approx Test Count |
|---|---|---|---|
| `test_model.nim` | `model.nim` | §14.1 | ~35 |
| `test_diagnostics.nim` | `diagnostics.nim` | §14.7 | ~10 |
| `test_validate.nim` | `validate.nim` | §14.2 | ~35 |
| `test_render_js.nim` | `render_js.nim` | §14.3 | ~35 |
| `test_render_package.nim` | `render_package.nim` | §14.4 | ~6 |
| `test_helpers.nim` | `helpers.nim` | §14.6 | ~6 |
| `test_export.nim` | `exporter.nim` | §14.5 | ~13 |
| `test_examples.nim` | Integration | §14.8 | ~7 |

Total: ~147 tests.

### 10.2 Snapshot Test Strategy

Snapshot tests compare rendered output against expected files stored in `tests/snapshots/`.

**Creating snapshots:**
1. Build the grammar in the test.
2. Render it with `renderGrammarJs()`.
3. Manually inspect the output for correctness.
4. Save as a `.js` file in `tests/snapshots/`.
5. The test reads the expected file and compares.

**Updating snapshots:**
When the renderer changes intentionally, re-generate and re-inspect snapshot files. Consider adding a flag or environment variable to auto-update snapshots during development.

### 10.3 Integration Tests with `tree-sitter`

Tests that invoke `tree-sitter generate` should check for the CLI first:

```nim
proc treeSitterAvailable(): bool =
  try:
    let (_, exitCode) = execCmdEx("tree-sitter --version")
    exitCode == 0
  except:
    false

test "tree-sitter generate produces parser":
  if not treeSitterAvailable():
    skip()
  # ... export and verify
```

---

## 11. Phase 10: Examples

**Directory:** `examples/`

### 11.1 `examples/arithmetic.nim`

A minimal arithmetic expression grammar demonstrating precedence and fields:

```nim
import treenimph

let grammar = Grammar(
  name = "arithmetic",
  rules = [
    Rule("expression", Choice(
      Ref("number"),
      Ref("binary_expression"),
      Ref("parenthesized_expression"),
    )),
    Rule("binary_expression", PrecLeft(1, Sequence(
      Field("left", Ref("expression")),
      Field("operator", Choice(Text("+"), Text("-"), Text("*"), Text("/"))),
      Field("right", Ref("expression")),
    ))),
    Rule("parenthesized_expression", balanced("(", ")", Ref("expression"))),
    Rule("number", Regex("[0-9]+")),
  ],
)

grammar.validateOrRaise()
echo grammar.renderGrammarJs()
```

### 11.2 `examples/json_like.nim`

A JSON-like grammar demonstrating objects, arrays, strings, numbers, and helpers:

```nim
import treenimph

let
  value = Ref("_value")
  comma = Text(",")

let grammar = Grammar(
  name = "json",
  extras = @[Regex("\\s+")],
  rules = [
    Rule("document", value),
    Rule("_value", Choice(
      Ref("object"),
      Ref("array"),
      Ref("string"),
      Ref("number"),
      Ref("true"),
      Ref("false"),
      Ref("null"),
    )),
    Rule("object", Sequence(
      Text("{"),
      Optional(delimitedList(Ref("pair"), comma, trailing = true)),
      Text("}"),
    )),
    Rule("pair", Sequence(
      Field("key", Ref("string")),
      Text(":"),
      Field("value", value),
    )),
    Rule("array", Sequence(
      Text("["),
      Optional(delimitedList(value, comma, trailing = true)),
      Text("]"),
    )),
    Rule("string", Sequence(
      Text("\""),
      ZeroOrMore(Choice(
        ImmediateToken(Regex("[^\"\\\\]+")),
        Ref("escape_sequence"),
      )),
      Text("\""),
    )),
    Rule("escape_sequence", ImmediateToken(Sequence(
      Text("\\"),
      Regex("[\"\\\\nrt/bfu]"),
    ))),
    Rule("number", Regex("-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?")),
    Rule("true", Text("true")),
    Rule("false", Text("false")),
    Rule("null", Text("null")),
  ],
)

grammar.validateOrRaise()
echo grammar.summary()
echo grammar.renderGrammarJs()
```

---

## 12. Cross-Cutting Concerns

### 12.1 Forward Declaration Order

Nim requires types to be declared before use. The `Expr` type is self-referential (`seq[Expr]` inside `Expr`), which is why it must be `ref object`. All types in `model.nim` should be in a single `type` block to allow mutual references if needed.

### 12.2 Import Hygiene

- Each module imports only what it needs.
- No circular imports. The dependency graph is a DAG:
  ```
  model.nim, diagnostics.nim  (leaf modules, no internal deps)
      ↓
  validate.nim  (depends on model, diagnostics)
  render_js.nim  (depends on model)
  render_package.nim  (depends on model)
  helpers.nim  (depends on model)
      ↓
  exporter.nim  (depends on model, validate, render_js, render_package, diagnostics)
      ↓
  treenimph.nim  (re-exports all)
  ```

### 12.3 Error Handling Philosophy

- **Constructors never raise.** They allow invalid states (empty names, nil children, empty sequences). This enables incremental construction.
- **Validation collects all errors.** No short-circuiting. Users see every problem at once.
- **Export fails early.** Validation runs first; if it fails, no files are written.
- **File operations raise on failure.** `ExportError` for any I/O issue.

### 12.4 Naming Conventions

| Layer | Convention | Examples |
|---|---|---|
| User-facing constructors | PascalCase | `Ref`, `Text`, `Sequence`, `Field` |
| Internal field names | camelCase with prefix | `refName`, `textValue`, `fieldExpr` |
| Accessor procs | camelCase | `inner`, `children`, `canonicalName` |
| Enum values | camelCase with prefix | `ekRef`, `assocLeft`, `dkError` |
| Validation procs | camelCase | `validate`, `validateOrRaise` |
| Render procs | camelCase | `renderGrammarJs`, `renderPackageJson` |

### 12.5 Performance Considerations

Performance is not a primary concern for a grammar authoring tool. Typical grammars have 20–200 rules. Even the largest Tree-sitter grammars (TypeScript, ~300 rules) process instantly.

That said, the design avoids unnecessary costs:
- Single `ref object` allocation per expression node (no vtable).
- Integer discriminator for `case` matching.
- No deep copying — expressions are `ref` and shared freely.
- Validation and rendering are single-pass traversals.

### 12.6 Thread Safety

TreeNimph v1 is single-threaded. `Expr` being `ref object` means expressions are not thread-safe by default. This is fine for the intended use case (CLI tool or build script).

### 12.7 Nim Version Compatibility

Target Nim 2.0.0+. Key language features used:
- `ref object` variants with `case` discriminator
- `varargs` in proc signatures
- `@` operator for varargs-to-seq conversion
- `std/options` for `Option[T]`
- `std/json` for JSON generation
- `std/osproc` for subprocess execution

---

## 13. Implementation Checklist

Use this checklist to track progress. Each item corresponds to a concrete deliverable.

### Project Setup
- [ ] Create directory structure
- [ ] Write `treenimph.nimble`
- [ ] Verify `nimble build` succeeds with empty source files

### Phase 1: Core Model
- [ ] Define `ExprKind` enum (14 variants)
- [ ] Define `Assoc` enum (4 variants)
- [ ] Define `Expr` ref object variant type
- [ ] Define `Rule` object type
- [ ] Define `QueryFiles` object type
- [ ] Define `Grammar` object type
- [ ] Define `ExportConfig` object type
- [ ] Implement all 17 expression constructor procs
- [ ] Implement `Rule` constructor with underscore convention
- [ ] Implement `Grammar` constructor with varargs
- [ ] Implement `ExportConfig` constructor with defaults
- [ ] Implement `inner` accessor
- [ ] Implement `children` accessor
- [ ] Implement `canonicalName` helper
- [ ] Implement `summary` introspection proc
- [ ] Write and pass all `test_model.nim` tests (~35 tests)

### Phase 2: Diagnostics
- [ ] Define `DiagnosticKind` enum
- [ ] Define `Diagnostic` object type
- [ ] Define `ValidationError` exception type
- [ ] Define `ExportError` exception type
- [ ] Implement `$` for `Diagnostic`
- [ ] Implement `error` and `warning` constructor helpers
- [ ] Implement `levenshteinDistance`
- [ ] Implement `findClosestMatch`
- [ ] Implement `newValidationError`
- [ ] Write and pass all `test_diagnostics.nim` tests (~10 tests)

### Phase 3: Validation
- [ ] Implement `isValidIdentifier` helper
- [ ] Implement `isValidRuleName` helper
- [ ] Implement `collectExternalRefs`
- [ ] Implement `validateGrammarLevel` (V01–V03)
- [ ] Implement `buildRuleNameSet` (V04–V08)
- [ ] Implement `validateExprTree` (V09–V16)
- [ ] Implement `validateGrammarConfig` (V17–V23)
- [ ] Implement `validate` top-level proc
- [ ] Implement `validateOrRaise` convenience proc
- [ ] Write and pass all `test_validate.nim` tests (~35 tests)

### Phase 4: JS Rendering
- [ ] Implement `escapeJsSingleQuote`
- [ ] Implement `escapeRegexSlash`
- [ ] Implement `indent` helper
- [ ] Implement `indentMultiline` helper
- [ ] Implement `renderExpr` for all 14 expression kinds
- [ ] Implement single-line/multi-line heuristic (80-char threshold)
- [ ] Implement `renderCallExpr` (seq, choice)
- [ ] Implement `renderWrapExpr` (optional, repeat, token, etc.)
- [ ] Implement `renderFieldExpr`
- [ ] Implement `renderAliasExpr`
- [ ] Implement `renderPrecExpr`
- [ ] Implement `renderGrammarJs` with all sections
- [ ] Verify deterministic output (same input → same output)
- [ ] Verify trailing commas on all items
- [ ] Verify header comment format
- [ ] Write and pass all `test_render_js.nim` tests (~35 tests)
- [ ] Create and verify snapshot test files

### Phase 5: Package Rendering
- [ ] Implement `renderPackageJson`
- [ ] Implement `renderTreeSitterJson`
- [ ] Verify JSON key order matches spec
- [ ] Verify 2-space indentation and trailing newline
- [ ] Write and pass all `test_render_package.nim` tests (~6 tests)

### Phase 6: Helpers
- [ ] Implement `delimitedList` (with and without trailing)
- [ ] Implement `optionalDelimitedList`
- [ ] Implement `balanced`
- [ ] Implement `keyword`
- [ ] Write and pass all `test_helpers.nim` tests (~6 tests)

### Phase 7: Export
- [ ] Implement file ownership detection helpers
- [ ] Implement `safeWrite` with ownership-aware overwrite
- [ ] Implement `writeQueryFile` (passthrough and stubs)
- [ ] Implement `exportGrammar` full flow (8 steps)
- [ ] Verify idempotency (two exports produce identical files)
- [ ] Write and pass all `test_export.nim` tests (~13 tests)

### Phase 8: Public API
- [ ] Write `treenimph.nim` with re-exports
- [ ] Verify `import treenimph` provides full API
- [ ] Verify all public symbols from Spec §13 are accessible

### Phase 9: Integration & Examples
- [ ] Write `examples/arithmetic.nim` — verify it compiles and produces valid output
- [ ] Write `examples/json_like.nim` — verify it compiles and produces valid output
- [ ] Write `examples/simple_lang.nim` — verify it compiles and produces valid output
- [ ] Write and pass all `test_examples.nim` integration tests (~7 tests)
- [ ] If `tree-sitter` CLI available: verify `tree-sitter generate` succeeds on exported grammars

### Final Verification
- [ ] All ~147 tests pass
- [ ] `nimble build` succeeds
- [ ] `nimble test` runs all test suites
- [ ] No compiler warnings
- [ ] Example grammars produce readable, correct `grammar.js`
- [ ] Exported packages have correct directory structure
- [ ] Snapshot tests match expected output

---

## Appendix A: Potential Pitfalls and How to Avoid Them

### A.1 Nim `varargs` + `openArray` Interaction

In the `Grammar` constructor, `rules` uses `varargs[Rule]` while other parameters use `openArray`. Nim allows this but the varargs parameter must come before any openArray parameters, or the compiler may have trouble distinguishing them. The signature in the spec places `rules` first after `name`, which is correct.

**If you encounter issues:** Change `rules` from `varargs[Rule]` to `openArray[Rule]` and require users to pass rules as an array literal: `rules = [rule1, rule2]`. This is a minor ergonomic regression but eliminates ambiguity.

### A.2 JSON Key Order

`std/json`'s `%*` macro uses `OrderedTable` internally in modern Nim, preserving insertion order. Verify this by inspecting the output. If keys appear in a different order than the spec, construct the JSON manually:

```nim
var j = newJObject()
j["name"] = %("tree-sitter-" & g.name)
j["version"] = %"0.1.0"
# ... etc, in order
```

### A.3 Regex Escaping in Rendered Output

The regex pattern in `Regex("\\s+")` — note the Nim string escape. In Nim source code, `"\\s+"` is the string `\s+`. The renderer wraps this in `/` delimiters, producing `/\s+/` in the JS output. This is correct.

Be careful with double-escaping: the Nim string `"\\\\s+"` is `\\s+` (literal backslash-s), which renders as `/\\s+/` in JS (also literal backslash-s). This matches intended semantics but can be confusing during testing.

### A.4 `export` is a Nim Keyword

The export module is named `exporter.nim` because `export` is reserved. The export proc is named `exportGrammar` to avoid conflicts. Users call `grammar.exportGrammar(config)`.

### A.5 Multi-Line Indentation in Rendered JS

The trickiest part of the renderer is correctly indenting multi-line nested expressions. The key insight: when rendering a child expression, pass the **child's** indent level. When the child decides to go multi-line, it uses its own indent level for its children. The parent only needs to indent the first line of the child.

Test this thoroughly with deeply nested structures: `Sequence(Field("x", Choice(Text("a"), Text("b"), Text("c"))))`.

### A.6 `ref` Object Equality

Two `Ref("foo")` calls produce two distinct `ref object` instances. `==` compares pointers by default. TreeNimph v1 does not define structural equality for `Expr`. Tests should compare fields, not objects:

```nim
# Correct:
check e.kind == ekRef
check e.refName == "identifier"

# Wrong (pointer comparison):
check e == Ref("identifier")  # will fail — different ref objects
```

If structural equality is desired for testing convenience, define `==` for `Expr`:

```nim
proc `==`*(a, b: Expr): bool =
  if a.isNil and b.isNil: return true
  if a.isNil or b.isNil: return false
  if a.kind != b.kind: return false
  case a.kind
  of ekRef: a.refName == b.refName
  of ekText: a.textValue == b.textValue
  # ... etc for all variants
```

This is optional for v1 but makes tests much more readable. Consider implementing it as a test utility rather than in the public API.
