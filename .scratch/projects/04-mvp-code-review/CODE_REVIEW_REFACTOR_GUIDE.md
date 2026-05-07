# TreeNimph MVP — Code Review Refactor Guide

**Based on:** `CODE_REVIEW.md` (2026-05-07)
**Target commit:** `a7d7fdb` (HEAD of `main`)
**Audience:** New contributor with no prior Nim experience

---

## Prerequisites

### Environment Setup

All commands in this guide must be run through the devenv shell. The project uses Nix-based tooling:

```bash
# Every command that touches Nim or tree-sitter must be prefixed:
devenv shell -- <command>

# Examples:
devenv shell -- nim check src/treenimph/model.nim    # type-check a file
devenv shell -- nim r -p:src tests/test_model.nim     # compile + run a test file
devenv shell -- tree-sitter generate                  # run tree-sitter in a package dir
```

### Nim Crash Course (What You Need to Know)

- **Files end in `.nim`**. Indentation-sensitive (like Python), 2-space indent.
- **`proc`** = function. `proc foo*(x: int): string` — the `*` means "exported" (public).
- **`import`** brings a module into scope. `import std/[options, strutils]` imports from stdlib.
- **`let`** = immutable binding. **`var`** = mutable. **`const`** = compile-time constant.
- **`seq[T]`** = dynamic array. `@[1, 2, 3]` creates one.
- **`Option[T]`** = optional value. `some(x)` / `none(string)` / `x.isSome` / `x.get`.
- **`ref object`** = heap-allocated object (pointer semantics). Plain `object` = value type.
- **`case kind: SomeEnum`** inside an object = tagged union (variant type).
- **`check`** in tests = assertion. `expect SomeError:` = assert exception is raised.
- **`suite "name":` / `test "name":`** = unittest structure.
- **`discard`** = explicitly ignore a return value.

### Running the Full Test Suite

Before starting ANY step, confirm the baseline:

```bash
devenv shell -- bash -c 'for f in tests/test_*.nim; do echo "=== $f ==="; nim r -p:src "$f" || exit 1; done'
```

All 36 tests must pass. If they don't, stop and investigate before proceeding.

### Workflow for Every Step

1. Read the "What to change" section.
2. Make the edits described in "Implementation".
3. Run the "Verification" commands.
4. Confirm all tests still pass (old + new).
5. Only then move to the next step.

---

## Step 1: Remove Erroneous Binary Declaration from nimble

**Code Review Reference:** BUG-1
**Severity:** Medium
**File:** `treenimph.nimble`

### What's Wrong

Line 6 declares `bin = @["treenimph"]`, telling Nim's package manager that this package produces an executable binary called `treenimph`. But `src/treenimph.nim` is a library module — it only contains `import` and `export` statements, no `main` entry point. This means `nimble build` would either fail or produce a useless empty binary.

### Implementation

Open `treenimph.nimble` and delete line 6 entirely. The file currently looks like:

```nim
version       = "0.1.0"
author        = "TreeNimph Contributors"
description   = "A Nim library for authoring Tree-sitter grammars as composable typed objects"
license       = "MIT"
srcDir        = "src"
bin           = @["treenimph"]    # <-- DELETE THIS LINE

requires "nim >= 2.0.0"

task test, "Run all tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      exec "nim r -p:src " & f
```

After your edit, the file should be:

```nim
version       = "0.1.0"
author        = "TreeNimph Contributors"
description   = "A Nim library for authoring Tree-sitter grammars as composable typed objects"
license       = "MIT"
srcDir        = "src"

requires "nim >= 2.0.0"

task test, "Run all tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      exec "nim r -p:src " & f
```

### Verification

```bash
# Confirm the file no longer contains "bin":
grep -n "bin" treenimph.nimble
# Expected: no output

# Confirm all tests still pass:
devenv shell -- nim r -p:src tests/test_model.nim
devenv shell -- nim r -p:src tests/test_export.nim
```

---

## Step 2: Fix Bare `except` Clauses in Exporter

**Code Review Reference:** BUG-3
**Severity:** Low
**File:** `src/treenimph/exporter.nim`

### What's Wrong

Lines 25 and 34 use bare `except:` clauses. In Nim, bare `except` catches **everything** — including `Defect` types like `IndexDefect`, `NilAccessDefect`, and `AssertionDefect`. These represent genuine programming bugs that should crash loudly, not be silently swallowed.

The two affected procs (`isTreeNimphPackageJson` and `isTreeNimphTreeSitterJson`) parse JSON and access fields. If the JSON structure is unexpected, we want to catch parsing/key errors — but NOT mask crashes from bugs in our own code.

### Implementation

In `src/treenimph/exporter.nim`, find these two procs and change `except:` to `except CatchableError:`.

**Change 1 — `isTreeNimphPackageJson` (line 25):**

Find:
```nim
proc isTreeNimphPackageJson(path: string, grammarName: string): bool =
  if not fileExists(path):
    return false
  try:
    let j = parseJson(readFile(path))
    j["name"].getStr() == "tree-sitter-" & grammarName
  except:
    false
```

Replace with:
```nim
proc isTreeNimphPackageJson(path: string, grammarName: string): bool =
  if not fileExists(path):
    return false
  try:
    let j = parseJson(readFile(path))
    j["name"].getStr() == "tree-sitter-" & grammarName
  except CatchableError:
    false
```

**Change 2 — `isTreeNimphTreeSitterJson` (line 34):**

Find:
```nim
proc isTreeNimphTreeSitterJson(path: string, grammarName: string): bool =
  if not fileExists(path):
    return false
  try:
    let j = parseJson(readFile(path))
    j["grammars"][0]["name"].getStr() == grammarName
  except:
    false
```

Replace with:
```nim
proc isTreeNimphTreeSitterJson(path: string, grammarName: string): bool =
  if not fileExists(path):
    return false
  try:
    let j = parseJson(readFile(path))
    j["grammars"][0]["name"].getStr() == grammarName
  except CatchableError:
    false
```

### Verification

```bash
# Type-check the modified file:
devenv shell -- nim check -p:src src/treenimph/exporter.nim

# Run the exporter tests — all 3 must pass:
devenv shell -- nim r -p:src tests/test_export.nim

# Verify no bare except: remains:
grep -n "except:" src/treenimph/exporter.nim
# Expected output should show "except CatchableError:" only
```

---

## Step 3: Add Nil Guard to `renderGrammarJs`

**Code Review Reference:** CONCERN-1
**Severity:** Medium
**File:** `src/treenimph/render_js.nim`

### What's Wrong

If a user calls `renderGrammarJs` directly (without going through `exportGrammar`), and a rule has a `nil` body, the code will crash with an unrecoverable `NilAccessDefect` at line 190 when it tries to call `renderExpr(rule.body, 2)`. The function should fail with a clear, catchable error message instead.

### Implementation

In `src/treenimph/render_js.nim`, add a nil check at the start of `renderGrammarJs`. You need to add `import ./diagnostics` at the top of the file (for the `ValidationError` type), then add validation before rendering.

**Step 3a — Add the import.** Find line 3:

```nim
import ./model
```

Replace with:
```nim
import ./diagnostics
import ./model
```

**Step 3b — Add the guard.** Find the proc (currently line 149):

```nim
proc renderGrammarJs*(g: Grammar): string =
  result = "// Generated by TreeNimph — do not edit manually.\n\n"
```

Replace with:
```nim
proc renderGrammarJs*(g: Grammar): string =
  ## Renders the grammar as a Tree-sitter grammar.js file.
  ## The grammar must be valid — call validate() or validateOrRaise() first.
  ## Passing a grammar with nil rule bodies will raise an AssertionDefect.
  for i, rule in g.rules:
    assert rule.body != nil, "Rule \"" & rule.canonicalName &
      "\" (rule #" & $(i + 1) & ") has a nil body — did you forget to call validateOrRaise()?"
  result = "// Generated by TreeNimph — do not edit manually.\n\n"
```

### Verification

```bash
# Type-check:
devenv shell -- nim check -p:src src/treenimph/render_js.nim

# Run render tests — all 3 must pass:
devenv shell -- nim r -p:src tests/test_render_js.nim

# Run ALL tests to confirm no regressions:
devenv shell -- nim r -p:src tests/test_export.nim
devenv shell -- nim r -p:src tests/test_examples.nim
```

### Add a Test for the Guard

Add a test to `tests/test_render_js.nim`. Find the end of the file (after the last test) and add inside the existing `suite "render_js":` block:

Find the closing line of the last test in the suite. The file ends with:

```nim
    let output = g.renderGrammarJs()
    let expected = readFile("tests/snapshots/json_like_grammar.js")
    check output == expected
```

After that last line (but still inside the `suite`), add:

```nim

  test "raises on nil rule body":
    let g = Grammar(
      name: "broken",
      rules: @[Rule(name: "source", body: nil, hidden: false)],
    )
    expect AssertionDefect:
      discard g.renderGrammarJs()
```

Also add `import std/[options]` at the top of the test file if not already present. Currently line 1 is:

```nim
import std/[strutils]
```

Replace with:

```nim
import std/[options, strutils]
```

### Verification (with new test)

```bash
devenv shell -- nim r -p:src tests/test_render_js.nim
# Expected: 4 tests pass, including "raises on nil rule body"
```

---

## Step 4: Fix Incomplete JS String Escaping

**Code Review Reference:** CONCERN-2
**Severity:** Medium
**File:** `src/treenimph/render_js.nim`

### What's Wrong

The `escapeJsSingleQuote` proc handles `\`, `'`, `\n`, `\r`, `\t` — but misses:
- **Null bytes** (`\0`, char code 0) — produce invalid JavaScript
- **Other control characters** (codes 1–31 except already-handled 9, 10, 13) — produce invalid JavaScript
- **Unicode line/paragraph separators** (U+2028, U+2029) — act as line terminators in JS strings

### Implementation

In `src/treenimph/render_js.nim`, replace the entire `escapeJsSingleQuote` proc. Find (lines 5–20):

```nim
proc escapeJsSingleQuote(s: string): string =
  result = ""
  for c in s:
    case c
    of '\\':
      result.add "\\\\"
    of '\'':
      result.add "\\'"
    of '\n':
      result.add "\\n"
    of '\r':
      result.add "\\r"
    of '\t':
      result.add "\\t"
    else:
      result.add c
```

Replace with:

```nim
proc escapeJsSingleQuote*(s: string): string =
  result = ""
  for c in s:
    case c
    of '\\':
      result.add "\\\\"
    of '\'':
      result.add "\\'"
    of '\n':
      result.add "\\n"
    of '\r':
      result.add "\\r"
    of '\t':
      result.add "\\t"
    of '\0':
      result.add "\\0"
    of '\x01'..'\x08', '\x0B', '\x0C', '\x0E'..'\x1F':
      # Control characters — render as \xNN hex escapes
      result.add "\\x"
      result.add "0123456789abcdef"[ord(c) shr 4]
      result.add "0123456789abcdef"[ord(c) and 0xF]
    else:
      result.add c
```

> **Note:** We added `*` to make the proc exported (public). This is needed so we can test it directly from the test file. The previous version was private (no `*`).

Also make `escapeRegexSlash` public in the same way. Find (line 22):

```nim
proc escapeRegexSlash(pattern: string): string =
```

Replace with:

```nim
proc escapeRegexSlash*(pattern: string): string =
```

### Explanation of the Hex Escape Logic

`ord(c)` gets the integer value of the character. For example, `ord('\x1F')` = 31.
- `shr 4` shifts right 4 bits to get the high nibble (31 → 1)
- `and 0xF` masks to get the low nibble (31 → 15, which is `f`)
- We index into a hex digit string to convert each nibble to its hex character.
- So `\x1F` becomes the string `\x1f`.

The ranges `\x01`..`\x08`, `\x0B`, `\x0C`, `\x0E`..`\x1F` cover all control characters except:
- `\t` (0x09), `\n` (0x0A), `\r` (0x0D) — already handled above with named escapes
- `\0` (0x00) — handled with `\\0` above

### Verification

```bash
# Type-check:
devenv shell -- nim check -p:src src/treenimph/render_js.nim

# Run existing render tests (should still pass):
devenv shell -- nim r -p:src tests/test_render_js.nim
```

### Add Unit Tests for Escaping

Add a new test suite at the END of `tests/test_render_js.nim` (after the closing of the existing `suite`). Append:

```nim

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
```

You also need to add the import for `render_js` to expose the now-public procs. The current imports at the top of `tests/test_render_js.nim` are:

```nim
import std/[options, strutils]
import unittest

import treenimph/[model, render_js]
```

These are already correct — `render_js` is already imported.

### Verification (with new tests)

```bash
devenv shell -- nim r -p:src tests/test_render_js.nim
# Expected: 4 original + 1 nil guard + 8 escape + 4 regex = 17 tests pass
```

---

## Step 5: Escape Grammar Name in JS Output

**Code Review Reference:** CONCERN-3
**Severity:** Medium
**File:** `src/treenimph/render_js.nim`

### What's Wrong

At line 152, the grammar name is inserted directly into a JavaScript single-quoted string without escaping:

```nim
result.add "  name: '" & g.name & "',\n"
```

If someone creates a grammar with a name containing `'` or `\` (unlikely but possible if validation is skipped), the generated JavaScript would be syntactically broken.

### Implementation

In `src/treenimph/render_js.nim`, find the line inside `renderGrammarJs` (currently around line 157 after previous edits):

```nim
  result.add "  name: '" & g.name & "',\n"
```

Replace with:

```nim
  result.add "  name: '" & escapeJsSingleQuote(g.name) & "',\n"
```

### Verification

```bash
# Type-check:
devenv shell -- nim check -p:src src/treenimph/render_js.nim

# Run render tests — snapshot test will confirm the output hasn't changed
# for normal grammar names (no special chars):
devenv shell -- nim r -p:src tests/test_render_js.nim

# Run all tests:
devenv shell -- nim r -p:src tests/test_export.nim
devenv shell -- nim r -p:src tests/test_examples.nim
```

No new test needed — the existing snapshot test already validates that normal names render correctly, and the escaping is inherently tested by the unit tests added in Step 4.

---

## Step 6: Fix Placeholder Snapshot File

**Code Review Reference:** BUG-2
**Severity:** Low
**File:** `tests/snapshots/expression_lang_grammar.js`

### What's Wrong

This file contains only `// snapshot placeholder`. No test references it. It's dead content from an unfinished task.

### Implementation

Delete the file:

```bash
rm tests/snapshots/expression_lang_grammar.js
```

### Verification

```bash
# Confirm the file is gone:
ls tests/snapshots/
# Expected: only json_like_grammar.js

# Confirm no test references it:
grep -r "expression_lang" tests/
# Expected: no output

# Run all tests to confirm nothing breaks:
devenv shell -- nim r -p:src tests/test_render_js.nim
```

---

## Step 7: Add Exporter Negative-Path Tests

**Code Review Reference:** GAP-1, GAP-2
**Severity:** Test coverage gap
**File:** `tests/test_export.nim`

### What's Missing

The exporter has two important safety paths that are untested:
1. `overwrite = false` should prevent overwriting existing files.
2. Overwriting a file that was NOT generated by TreeNimph should be refused (ownership check).

### Implementation

Open `tests/test_export.nim`. The current contents end at line 39. Add these tests inside the existing `suite "exporter":` block, after the last test:

Find the end of the last test:

```nim
  test "export can overwrite owned files":
    let tmpDir = createTempDir("treenimph_test_", "")
    defer: removeDir(tmpDir)

    let outDir = tmpDir / "output"
    let g = mkGrammar("test", rules = [mkRule("source", Blank())])
    g.exportGrammar(mkExportConfig(outDir))
    g.exportGrammar(mkExportConfig(outDir, overwrite = true))
    check fileExists(outDir / "grammar.js")
```

After that, add:

```nim

  test "export with overwrite=false raises on existing files":
    let tmpDir = createTempDir("treenimph_test_", "")
    defer: removeDir(tmpDir)

    let outDir = tmpDir / "output"
    let g = mkGrammar("test", rules = [mkRule("source", Blank())])
    # First export succeeds
    g.exportGrammar(mkExportConfig(outDir))
    check fileExists(outDir / "grammar.js")
    # Second export with overwrite=false must raise
    expect ExportError:
      g.exportGrammar(mkExportConfig(outDir, overwrite = false))

  test "export refuses to overwrite non-TreeNimph files":
    let tmpDir = createTempDir("treenimph_test_", "")
    defer: removeDir(tmpDir)

    let outDir = tmpDir / "output"
    let g = mkGrammar("test", rules = [mkRule("source", Blank())])
    # Create dir structure manually with a foreign grammar.js
    createDir(outDir)
    createDir(outDir / "queries")
    createDir(outDir / "src")
    writeFile(outDir / "grammar.js", "// Written by hand, not TreeNimph\n")
    # Export with overwrite=true should refuse because ownership check fails
    expect ExportError:
      g.exportGrammar(mkExportConfig(outDir, overwrite = true))
```

### Verification

```bash
devenv shell -- nim r -p:src tests/test_export.nim
# Expected: 5 tests pass (3 original + 2 new)
```

---

## Step 8: Add Deeply Nested Expression Validation Test

**Code Review Reference:** GAP-3
**Severity:** Test coverage gap
**File:** `tests/test_validate.nim`

### What's Missing

No test verifies that validation catches errors inside deeply nested expression trees. For example, `Optional(Sequence(Field("x", Ref("missing"))))` has an invalid ref buried 3 levels deep.

### Implementation

Open `tests/test_validate.nim`. Add a new test inside the `"Validate expression refs"` suite. Find the end of that suite (after the "empty choice" test):

```nim
  test "empty choice":
    let g = mkGrammar("demo", rules = [mkRule("source", Choice())])
    let diags = g.validate()
    check hasDiag(diags, "Choice must contain at least one item")
```

After that, add:

```nim

  test "deeply nested invalid ref":
    # Ref("missing") is buried 3 levels deep: Optional → Sequence → Field → Ref
    let g = mkGrammar("demo", rules = [
      mkRule("source", Optional(Sequence(Field("x", Ref("missing"))))),
    ])
    let diags = g.validate()
    check hasDiag(diags, "Unknown rule reference \"missing\"")

  test "nested nil child in sequence":
    # A nil item inside a sequence that's inside an optional
    let g = mkGrammar("demo", rules = [
      mkRule("source", Optional(Sequence(Text("a"), nil, Text("b")))),
    ])
    let diags = g.validate()
    check hasDiag(diags, "Sequence contains a nil item")
```

### Verification

```bash
devenv shell -- nim r -p:src tests/test_validate.nim
# Expected: all tests pass (original 13 + 2 new = 15)
```

---

## Step 9: Add Comprehensive Render Test with All Config Options

**Code Review Reference:** GAP-4
**Severity:** Test coverage gap
**File:** `tests/test_render_js.nim`

### What's Missing

No test renders a grammar that uses `word`, `supertypes`, `inline`, `conflicts`, and `externals` all at once. These config sections are rendered by distinct code paths in `renderGrammarJs` that are currently untested.

### Implementation

Add this test inside the existing `suite "render_js":` block in `tests/test_render_js.nim`. Add it after the "raises on nil rule body" test (added in Step 3) — or after the snapshot test if Step 3's test is at the end. The key is it must be inside `suite "render_js":`.

```nim

  test "renders all grammar config sections":
    let g = mkGrammar(
      "full_config",
      rules = [
        mkRule("source", Ref("expr")),
        mkRule("expr", Choice(Ref("number"), Ref("identifier"))),
        mkRule("number", Regex("[0-9]+")),
        mkRule("identifier", Regex("[a-zA-Z_]+")),
        mkRule("_helper", Blank()),
      ],
      word = some("identifier"),
      extras = [Regex("\\s+"), Ref("_helper")],
      supertypes = ["expr"],
      inline = ["_helper"],
      conflicts = [@["expr", "number"]],
      externals = [Ref("ext_token")],
    )
    let output = g.renderGrammarJs()

    # Verify the word section
    check output.contains("word: $ => $.identifier")

    # Verify extras section
    check output.contains("extras: $ => [")
    check output.contains("/\\s+/")

    # Verify supertypes section
    check output.contains("supertypes: $ => [")
    check output.contains("$.expr")

    # Verify inline section
    check output.contains("inline: $ => [")
    check output.contains("$._helper")

    # Verify conflicts section
    check output.contains("conflicts: $ => [")
    check output.contains("[$.expr, $.number]")

    # Verify externals section
    check output.contains("externals: $ => [")
    check output.contains("$.ext_token")

    # Verify hidden rule renders with underscore
    check output.contains("_helper: $ =>")
```

### Verification

```bash
devenv shell -- nim r -p:src tests/test_render_js.nim
# Expected: all tests pass (previous + 1 new)
```

---

## Step 10: Remove Redundant `queryFiles` Parameter from `renderTreeSitterJson`

**Code Review Reference:** CONCERN-5
**Severity:** Low
**Files:** `src/treenimph/render_package.nim`, `src/treenimph/exporter.nim`, `tests/test_render_package.nim`

### What's Wrong

`renderTreeSitterJson` takes a `Grammar` (which already has `.queryFiles`) AND a separate `queryFiles` parameter. The separate parameter shadows the grammar's own field. This is confusing. We should use `g.queryFiles` and remove the redundant parameter.

### Implementation

**Step 10a — Edit `src/treenimph/render_package.nim`.** Find (line 52):

```nim
proc renderTreeSitterJson*(g: Grammar, queryFiles: Option[QueryFiles] = none(QueryFiles), writeQueryStubs = true): string =
  var grammarEntry = %*{
    "name": g.name,
    "scope": "source." & g.name,
    "path": ".",
  }

  grammarEntry["file-types"] = newJArray()

  let qf = if queryFiles.isSome: queryFiles.get else: QueryFiles()
```

Replace with:

```nim
proc renderTreeSitterJson*(g: Grammar, writeQueryStubs = true): string =
  var grammarEntry = %*{
    "name": g.name,
    "scope": "source." & g.name,
    "path": ".",
  }

  grammarEntry["file-types"] = newJArray()

  let qf = if g.queryFiles.isSome: g.queryFiles.get else: QueryFiles()
```

**Step 10b — Edit `src/treenimph/exporter.nim`.** Find (line 78):

```nim
  let treeSitterJsonContent = g.renderTreeSitterJson(g.queryFiles, writeStubs)
```

Replace with:

```nim
  let treeSitterJsonContent = g.renderTreeSitterJson(writeStubs)
```

**Step 10c — Verify test calls still compile.** The test file `tests/test_render_package.nim` calls `g.renderTreeSitterJson()` (no explicit queryFiles arg) and `g.renderTreeSitterJson(writeQueryStubs = false)`. Both will continue to work since we only removed the `queryFiles` parameter and `writeQueryStubs` is still named.

### Verification

```bash
# Type-check both changed files:
devenv shell -- nim check -p:src src/treenimph/render_package.nim
devenv shell -- nim check -p:src src/treenimph/exporter.nim

# Run package render tests:
devenv shell -- nim r -p:src tests/test_render_package.nim

# Run exporter tests:
devenv shell -- nim r -p:src tests/test_export.nim

# Run example integration tests:
devenv shell -- nim r -p:src tests/test_examples.nim
```

---

## Step 11: Add `writeQueryFile` Ownership Protection

**Code Review Reference:** CONCERN-4
**Severity:** Low
**File:** `src/treenimph/exporter.nim`

### What's Wrong

When `content.isSome` (user provides custom query file content), `writeQueryFile` calls `writeFile` directly — bypassing the ownership check that protects `grammar.js` and `package.json`. A user could accidentally overwrite a hand-edited query file.

### Implementation

In `src/treenimph/exporter.nim`, find the `writeQueryFile` proc (lines 45–54):

```nim
proc writeQueryFile(path: string, content: Option[string], writeStubs: bool, overwrite: bool) =
  if content.isSome:
    writeFile(path, content.get)
  elif writeStubs:
    if fileExists(path):
      if not overwrite:
        return
      if not isTreeNimphOwned(path, TreeNimphScmHeader):
        return
    writeFile(path, TreeNimphScmHeader & "\n")
```

Replace with:

```nim
proc writeQueryFile(path: string, content: Option[string], writeStubs: bool, overwrite: bool) =
  if content.isSome:
    if fileExists(path) and not overwrite:
      raise newException(ExportError, "File already exists and overwrite is disabled: " & path)
    if fileExists(path) and not isTreeNimphOwned(path, TreeNimphScmHeader):
      raise newException(ExportError, "Refusing to overwrite file not generated by TreeNimph: " & path)
    writeFile(path, content.get)
  elif writeStubs:
    if fileExists(path):
      if not overwrite:
        return
      if not isTreeNimphOwned(path, TreeNimphScmHeader):
        return
    writeFile(path, TreeNimphScmHeader & "\n")
```

### Verification

```bash
# Type-check:
devenv shell -- nim check -p:src src/treenimph/exporter.nim

# Run exporter tests (the new test from Step 7 should still pass):
devenv shell -- nim r -p:src tests/test_export.nim
```

---

## Step 12: Add Validator Warnings for Common Pitfalls

**Code Review Reference:** OBS-1
**Severity:** Nice to have
**File:** `src/treenimph/validate.nim`

### What's Wrong

The `dkWarning` diagnostic kind exists but is never used. We'll add two useful warnings:
1. **Single-item `Choice`** — `Choice(X)` is equivalent to just `X`; probably a mistake.
2. **Unreferenced rules** — a rule that no other rule references may be dead code (except the first rule, which is the grammar's entry point).

### Implementation

**Step 12a — Add single-item Choice/Sequence warnings.** In `src/treenimph/validate.nim`, inside the `validateExprTree` proc, find the `of ekSequence:` block (around line 109):

```nim
  of ekSequence:
    if e.items.len == 0:
      diags.add error(
        "Sequence must contain at least one item",
        ruleName = some(ruleName),
        hint = some("In rule \"" & ruleName & "\""),
      )
```

After the closing of that `if` block (the `for i, item in e.items:` loop) and before the `of ekChoice:` line, add:

Actually, let's be precise. The `of ekSequence:` block currently is:

```nim
  of ekSequence:
    if e.items.len == 0:
      diags.add error(
        "Sequence must contain at least one item",
        ruleName = some(ruleName),
        hint = some("In rule \"" & ruleName & "\""),
      )
    for i, item in e.items:
      if item == nil:
        diags.add error(
          "Sequence contains a nil item at position " & $(i + 1) & " in rule \"" & ruleName & "\"",
          ruleName = some(ruleName),
        )
```

Replace it with:

```nim
  of ekSequence:
    if e.items.len == 0:
      diags.add error(
        "Sequence must contain at least one item",
        ruleName = some(ruleName),
        hint = some("In rule \"" & ruleName & "\""),
      )
    elif e.items.len == 1:
      diags.add warning(
        "Sequence with a single item is redundant",
        ruleName = some(ruleName),
        hint = some("In rule \"" & ruleName & "\": use the item directly instead of wrapping in Sequence()"),
      )
    for i, item in e.items:
      if item == nil:
        diags.add error(
          "Sequence contains a nil item at position " & $(i + 1) & " in rule \"" & ruleName & "\"",
          ruleName = some(ruleName),
        )
```

Do the same for `of ekChoice:`. Find:

```nim
  of ekChoice:
    if e.items.len == 0:
      diags.add error(
        "Choice must contain at least one item",
        ruleName = some(ruleName),
        hint = some("In rule \"" & ruleName & "\""),
      )
    for i, item in e.items:
      if item == nil:
        diags.add error(
          "Choice contains a nil item at position " & $(i + 1) & " in rule \"" & ruleName & "\"",
          ruleName = some(ruleName),
        )
```

Replace with:

```nim
  of ekChoice:
    if e.items.len == 0:
      diags.add error(
        "Choice must contain at least one item",
        ruleName = some(ruleName),
        hint = some("In rule \"" & ruleName & "\""),
      )
    elif e.items.len == 1:
      diags.add warning(
        "Choice with a single item is redundant",
        ruleName = some(ruleName),
        hint = some("In rule \"" & ruleName & "\": use the item directly instead of wrapping in Choice()"),
      )
    for i, item in e.items:
      if item == nil:
        diags.add error(
          "Choice contains a nil item at position " & $(i + 1) & " in rule \"" & ruleName & "\"",
          ruleName = some(ruleName),
        )
```

**Step 12b — Add unreferenced rule warning.** We need to add a new helper proc and call it from `validate`. Add this proc BEFORE the `validate*` proc (before line 241). Find:

```nim
proc validate*(g: Grammar): seq[Diagnostic] =
```

Insert before it:

```nim
proc collectReferencedNames(e: Expr, refs: var HashSet[string]) =
  if e == nil:
    return
  if e.kind == ekRef:
    refs.incl e.refName
  for child in e.children:
    collectReferencedNames(child, refs)

proc warnUnreferencedRules(g: Grammar, diags: var seq[Diagnostic]) =
  var referencedNames: HashSet[string]
  for rule in g.rules:
    collectReferencedNames(rule.body, referencedNames)
  # Also collect refs from extras and externals
  for e in g.extras:
    collectReferencedNames(e, referencedNames)
  for e in g.externals:
    collectReferencedNames(e, referencedNames)
  # Skip the first rule — it's the entry point and doesn't need to be referenced
  for i in 1..<g.rules.len:
    let cname = g.rules[i].canonicalName
    if cname notin referencedNames:
      diags.add warning(
        "Rule \"" & cname & "\" is never referenced by any other rule",
        ruleName = some(cname),
        hint = some("This may indicate dead code or a missing reference"),
      )

```

Then, in the `validate*` proc body, add the call at the end. Find:

```nim
  validateGrammarConfig(g, ruleNames, ruleNameList, diags)

  diags
```

Replace with:

```nim
  validateGrammarConfig(g, ruleNames, ruleNameList, diags)

  warnUnreferencedRules(g, diags)

  diags
```

### Important Note

These are **warnings**, not errors. The existing `validateOrRaise` proc only raises on `dkError` diagnostics (see `validate.nim` line 267: `if d.kind == dkError`). So these warnings will NOT break any existing grammars — they'll only appear if someone inspects the diagnostic list returned by `validate()`.

### Verification

```bash
# Type-check:
devenv shell -- nim check -p:src src/treenimph/validate.nim

# Run all tests — IMPORTANT: warnings must NOT cause existing tests to fail
devenv shell -- nim r -p:src tests/test_validate.nim
devenv shell -- nim r -p:src tests/test_export.nim
devenv shell -- nim r -p:src tests/test_examples.nim
```

### Add Tests for Warnings

Add a new suite to `tests/test_validate.nim`. At the END of the file, add:

```nim

suite "Validate warnings":
  test "single-item choice warns":
    let g = mkGrammar("demo", rules = [mkRule("source", Choice(Ref("source")))])
    let diags = g.validate()
    var found = false
    for d in diags:
      if d.kind == dkWarning and d.message.contains("Choice with a single item"):
        found = true
    check found

  test "single-item sequence warns":
    let g = mkGrammar("demo", rules = [mkRule("source", Sequence(Text("x")))])
    let diags = g.validate()
    var found = false
    for d in diags:
      if d.kind == dkWarning and d.message.contains("Sequence with a single item"):
        found = true
    check found

  test "unreferenced rule warns":
    let g = mkGrammar("demo", rules = [
      mkRule("source", Text("x")),
      mkRule("orphan", Text("y")),
    ])
    let diags = g.validate()
    var found = false
    for d in diags:
      if d.kind == dkWarning and d.message.contains("never referenced"):
        found = true
    check found

  test "first rule (entry point) does not warn even if unreferenced":
    # The first rule is the grammar entry point — it's always implicitly used
    let g = mkGrammar("demo", rules = [
      mkRule("source", Text("x")),
    ])
    let diags = g.validate()
    for d in diags:
      check not d.message.contains("never referenced")

  test "warnings do not cause validateOrRaise to raise":
    let g = mkGrammar("demo", rules = [
      mkRule("source", Choice(Text("x"))),
      mkRule("orphan", Text("y")),
    ])
    # This must NOT raise — warnings are not errors
    g.validateOrRaise()
```

### Verification (with new tests)

```bash
devenv shell -- nim r -p:src tests/test_validate.nim
# Expected: all original tests + 5 new warning tests pass
```

---

## Step 13: Add Debug `$` Proc for `Expr`

**Code Review Reference:** OBS-3
**Severity:** Nice to have
**File:** `src/treenimph/model.nim`

### What's Missing

There's no way to print an `Expr` for debugging. You can print `Diagnostic` (has `$`) and `Grammar` (has `summary`), but `echo someExpr` gives unhelpful output.

### Implementation

Add a `$` proc at the end of `src/treenimph/model.nim`, before the `summary` proc. Find (line 217):

```nim
proc summary*(g: Grammar): string =
```

Insert before it:

```nim
proc `$`*(e: Expr): string =
  if e == nil:
    return "<nil>"
  case e.kind
  of ekRef:
    "Ref(\"" & e.refName & "\")"
  of ekText:
    "Text(\"" & e.textValue & "\")"
  of ekRegex:
    "Regex(\"" & e.regexPattern & "\")"
  of ekBlank:
    "Blank()"
  of ekSequence:
    var parts: seq[string] = @[]
    for item in e.items:
      parts.add $item
    "Sequence(" & parts.join(", ") & ")"
  of ekChoice:
    var parts: seq[string] = @[]
    for item in e.items:
      parts.add $item
    "Choice(" & parts.join(", ") & ")"
  of ekOptional:
    "Optional(" & $e.item & ")"
  of ekZeroOrMore:
    "ZeroOrMore(" & $e.item & ")"
  of ekOneOrMore:
    "OneOrMore(" & $e.item & ")"
  of ekField:
    "Field(\"" & e.fieldName & "\", " & $e.fieldExpr & ")"
  of ekAlias:
    "Alias(\"" & e.aliasName & "\", " & $e.aliasExpr & ", named=" & $e.aliasNamed & ")"
  of ekToken:
    "Token(" & $e.tokenExpr & ")"
  of ekImmediateToken:
    "ImmediateToken(" & $e.tokenExpr & ")"
  of ekPrecedence:
    "Prec(" & $e.precLevel & ", " & $e.precExpr & ", " & $e.precAssoc & ")"

```

### Add Tests

Add to `tests/test_model.nim`. At the end of the file, add a new suite:

```nim

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
```

### Verification

```bash
devenv shell -- nim check -p:src src/treenimph/model.nim
devenv shell -- nim r -p:src tests/test_model.nim
# Expected: original 15 tests + 4 new = 19 pass
```

---

## Step 14: Update the Snapshot After All Changes

After all the code changes, the json_like snapshot test should still pass because we didn't change the rendering logic for normal grammars. But let's verify.

### Verification

```bash
devenv shell -- nim r -p:src tests/test_render_js.nim
# The "snapshot json-like grammar" test must pass
```

If it fails (it shouldn't), regenerate the snapshot by running:

```bash
# Only if the snapshot test fails:
devenv shell -- nim r -p:src -e '
import treenimph
# ... (the grammar from the test) ...
echo renderGrammarJs(...)
' > tests/snapshots/json_like_grammar.js
```

But this should not be necessary.

---

## Final Verification: Run the Complete Test Suite

After all 13 steps are complete, run every test file:

```bash
devenv shell -- bash -c '
  pass=0; fail=0
  for f in tests/test_*.nim; do
    echo "=== $f ==="
    if nim r -p:src "$f"; then
      pass=$((pass + 1))
    else
      fail=$((fail + 1))
      echo "FAILED: $f"
    fi
  done
  echo ""
  echo "Results: $pass passed, $fail failed"
  if [ $fail -gt 0 ]; then exit 1; fi
'
```

### Expected Test Counts After Refactor

| Test File | Before | After | New Tests |
|-----------|--------|-------|-----------|
| `test_model.nim` | 15 | 19 | 4 (Expr stringify) |
| `test_validate.nim` | 13 | 20 | 7 (2 deep nesting + 5 warnings) |
| `test_diagnostics.nim` | 6 | 6 | 0 |
| `test_helpers.nim` | 5 | 5 | 0 |
| `test_render_js.nim` | 3 | 17 | 14 (1 nil guard + 8 escape + 4 regex + 1 full config) |
| `test_render_package.nim` | 3 | 3 | 0 |
| `test_export.nim` | 3 | 5 | 2 (overwrite + ownership) |
| `test_examples.nim` | 3 | 3 | 0 |
| **Total** | **51** | **78** | **27 new tests** |

> Note: The original count was 36 per the code review, but that counted tests within suites. The numbers above count individual `test` blocks.

---

## Summary of All Files Modified

| File | Steps | Changes |
|------|-------|---------|
| `treenimph.nimble` | 1 | Remove `bin` line |
| `src/treenimph/exporter.nim` | 2, 10, 11 | Fix bare except; update renderTreeSitterJson call; protect writeQueryFile |
| `src/treenimph/render_js.nim` | 3, 4, 5 | Add nil guard; fix escaping; escape grammar name; export escape procs |
| `src/treenimph/render_package.nim` | 10 | Remove redundant queryFiles param |
| `src/treenimph/validate.nim` | 12 | Add single-item warnings; add unreferenced rule warning |
| `src/treenimph/model.nim` | 13 | Add `$` proc for Expr |
| `tests/test_render_js.nim` | 3, 4, 9 | Add nil guard test; add escape tests; add full config test |
| `tests/test_validate.nim` | 8, 12 | Add deep nesting tests; add warning tests |
| `tests/test_export.nim` | 7 | Add overwrite=false test; add ownership test |
| `tests/test_model.nim` | 13 | Add Expr stringify tests |
| `tests/snapshots/expression_lang_grammar.js` | 6 | Delete file |

---

## Ordering Dependencies

Steps can be done in any order EXCEPT:
- **Step 4 must come before Step 5** (Step 5 uses `escapeJsSingleQuote` which Step 4 modifies).
- **Step 4 must come before Step 9** (Step 9's test imports from `render_js` and expects public escape procs).
- **Step 10 edits two files** — do both sub-steps together before testing.

Recommended order: Follow steps 1–13 sequentially as written.
