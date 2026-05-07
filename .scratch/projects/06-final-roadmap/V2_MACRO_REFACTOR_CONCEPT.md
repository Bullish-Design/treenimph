# TreeNimph v2: Macro DSL Concept

**Date:** 2026-05-07
**Status:** Concept / Design
**Baseline:** `2bdbc53` (MVP complete)

---

## Motivation

The current TreeNimph API works, but grammar files feel like "Nim programs that use a library" rather than "grammar definition files." The boilerplate at the tail of every example (`grammar.validateOrRaise()`, `echo grammar.renderGrammarJs()`) reinforces this — as does the ceremony of `Ref("name")`, `Text("let")`, `Sequence(...)`, and `mkRule("name", ...)` throughout the body.

The goal is to make grammar files feel **native** — like they exist for one purpose: defining a Tree-sitter grammar. The library should handle everything else automatically.

---

## What Grammar Files Should Look Like

### Simple language

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

### JSON

```nim
import treenimph/dsl

grammar "json":
  extras = [re"\\s+"]

  let value = _value
  let comma = ","

  document = value
  _value = object | array | string | number | true_lit | false_lit | null_lit
  object = ["{", ?delimitedList(pair, comma, trailing = true), "}"]
  pair = [key@string, ":", value@value]
  array = ["[", ?delimitedList(value, comma, trailing = true), "]"]
  string = re"\"[^\"]*\""
  number = re"-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?"
  true_lit = "true"
  false_lit = "false"
  null_lit = "null"
```

### Arithmetic with precedence

```nim
import treenimph/dsl

grammar "arithmetic":
  expression = number | binary_expression | parenthesized_expression
  binary_expression = prec_left(1, [left@expression, operator@("+" | "-" | "*" | "/"), right@expression])
  parenthesized_expression = ["(", expression, ")"]
  number = re"[0-9]+"
```

### What makes this feel "native"

1. **No trailing boilerplate.** The `grammar` macro handles validation, CLI dispatch, and output — the file is just a definition.
2. **No `Ref()` calls.** Bare identifiers (`statement`, `identifier`) become references automatically.
3. **No `Text()` calls.** String literals (`"let"`, `";"`) become text nodes automatically.
4. **No `mkRule()` wrapper.** Each line `name = body` is a rule.
5. **No `Sequence()` wrapper.** Bracket syntax (`[a, b, c]`) is the sequence.
6. **Operators for grammar constructs.** `|` for choice, `?` for optional, `*`/`+` for repetition, `@` for fields.
7. **Hidden rules just work.** `_value = ...` automatically sets `hidden = true`.

---

## DSL Syntax Reference

### Rules

```
rule_name = body              # named rule
_hidden_rule = body           # hidden rule (underscore prefix)
```

Each `name = expr` assignment in the grammar block becomes a `mkRule(name, body)` call. Names starting with `_` get `hidden = true` automatically (this is already how `mkRule` works).

### References

```
statement                     # bare identifier -> Ref("statement")
_value                        # underscore-prefixed -> Ref("_value")
```

Any bare identifier on the right-hand side of a rule that is not a `let`-bound variable or a recognized keyword becomes `Ref("that_name")`.

### Text literals

```
"let"                         # string literal -> Text("let")
";"                           # string literal -> Text(";")
```

### Regex

```
re"[a-zA-Z_]+"               # generalized string literal -> Regex("...")
```

Nim natively parses `re"..."` as a `nnkCallStrLit` node. The macro recognizes this and emits `Regex(...)`.

### Sequences (bracket syntax)

```
[item1, item2, item3]         # -> Sequence(item1, item2, item3)
```

Nim parses `[a, b, c]` as `nnkBracket`. The macro converts this to `Sequence(...)` with each element recursively transformed. Single-element brackets are allowed but produce a single expression (no Sequence wrapper).

### Choice

```
a | b | c                     # -> Choice(a, b, c)
```

The `|` infix operator. Chains are flattened: `a | b | c` (which Nim parses as `(a | b) | c`) becomes `Choice(a, b, c)`.

### Optional

```
?trailing_comma               # prefix ? -> Optional(...)
```

### Zero-or-more / One-or-more

```
*statement                    # prefix * -> ZeroOrMore(...)
+digit                        # prefix + -> OneOrMore(...)
```

### Fields

```
name@identifier               # infix @ -> Field("name", Ref("identifier"))
left@expression               # Field("left", Ref("expression"))
value@("a" | "b")            # Field("value", Choice(Text("a"), Text("b")))
```

The `@` operator is valid Nim infix. The left-hand side must be a bare identifier (the field name); the right-hand side is recursively transformed.

### Precedence

```
prec(1, expr)                 # Prec(1, expr)
prec_left(1, expr)            # PrecLeft(1, expr)
prec_right(1, expr)           # PrecRight(1, expr)
prec_dynamic(1, expr)         # PrecDynamic(1, expr)
```

These remain as function-call syntax. The macro recognizes `prec`, `prec_left`, `prec_right`, `prec_dynamic` as special names: the first argument (precedence level) is passed through as-is; subsequent arguments are recursively transformed.

### Token / ImmediateToken

```
token(expr)                   # Token(expr)
immediate_token(expr)         # ImmediateToken(expr)
```

Same pattern as precedence — recognized call names with argument transformation.

### Alias

```
alias("name", expr)           # Alias("name", expr, named = true)
alias("name", expr, named = false)
```

### Helpers

```
delimitedList(pair, comma)                  # args transformed, call preserved
optionalDelimitedList(value, comma)
balanced("(", ")", expression)
```

Any unrecognized function call is treated as a passthrough: the macro transforms the arguments but leaves the call structure intact. This means existing helpers (and any new ones) work automatically inside the DSL without special handling.

### `let` bindings for reusable sub-expressions

```nim
grammar "json":
  let value = _value           # desugars to: let value = Ref("_value")
  let comma = ","              # desugars to: let comma = Text(",")

  document = value             # uses the variable, NOT Ref("value")
```

The macro tracks `let`-bound names. When it encounters a bare identifier that matches a `let`-bound name, it leaves it as-is (the Nim compiler resolves the variable). All other bare identifiers become `Ref()` calls.

`let` binding right-hand sides are also transformed through the DSL rules, so `let value = _value` becomes `let value = Ref("_value")` and `let comma = ","` becomes `let comma = Text(",")`.

### Grammar-level configuration

```nim
grammar "my_lang":
  extras = [re"\\s+", re"//[^\\n]*"]
  word = identifier
  conflicts = [[expression, binary_expression]]
  supertypes = [_expression, _statement]
  inline = [_binary_op]

  # rules follow...
  source_file = *statement
```

The macro recognizes these reserved names as grammar configuration rather than rules:
- `extras` — list of `Expr` (transformed)
- `word` — single identifier (becomes a string)
- `conflicts` — list of lists of identifiers (become strings)
- `supertypes` — list of identifiers (become strings)
- `inline` — list of identifiers (become strings)
- `externals` — list of identifiers/expressions (transformed)
- `scannerPath` — string literal (passed through)
- `queryFiles` — passed through as-is (raw `QueryFiles` value)

These names cannot be used as rule names within the DSL. This is acceptable since none of them would be natural rule names.

---

## Operator Precedence

Nim's operator precedence (determined by first character) works perfectly for grammar DSL:

| Operator | Nim precedence | Grammar meaning |
|---|---|---|
| `*`, `+` (prefix) | Highest (unary) | Repetition |
| `?` (prefix) | Highest (unary) | Optional |
| `@` (infix) | Level 7 | Field binding |
| `\|` (infix) | Level 4 | Choice |

Binding order: `?name@expr | *other` parses as `(?(name@expr)) | (*other)` — correct.

Within brackets (sequences), items are comma-separated so operator precedence only applies within each item: `[a, b | c, ?d]` means `Sequence(a, Choice(b, c), Optional(d))` — correct.

---

## CLI / Runner Behavior

The `grammar` macro generates a complete `main` body that:

1. Validates the grammar (raises `ValidationError` on errors, prints warnings to stderr)
2. Parses CLI arguments to determine action:
   - **No args (default):** Print `grammar.js` to stdout
   - `--export <dir>`: Full package export to directory
   - `--summary`: Print grammar summary
   - `--validate`: Validate only (exit 0 if clean, exit 1 if errors)
3. Executes the action

This means grammar files are directly executable:

```bash
nim r examples/simple_lang.nim                        # prints grammar.js
nim r examples/simple_lang.nim --export out/          # full package export
nim r examples/simple_lang.nim --summary              # prints summary
nim r examples/simple_lang.nim --validate             # validate only
```

---

## Architecture: What Changes, What Doesn't

### Unchanged (core library)

These modules form the stable foundation. **No modifications needed:**

| Module | Role |
|---|---|
| `model.nim` | Core types: `Expr`, `Rule`, `Grammar`, `ExportConfig`, constructors |
| `diagnostics.nim` | `Diagnostic`, `ValidationError`, `ExportError`, formatting |
| `validate.nim` | `validate()`, `validateOrRaise()` |
| `render_js.nim` | `renderGrammarJs()` |
| `render_package.nim` | `renderPackageJson()`, `renderTreeSitterJson()` |
| `exporter.nim` | `exportGrammar()` |
| `helpers.nim` | `delimitedList`, `balanced`, etc. |

The entire existing API surface is untouched. Users who prefer the explicit object-construction style can continue using `import treenimph` exactly as before.

### New modules

| Module | Role | Complexity |
|---|---|---|
| `treenimph/dsl.nim` | The `grammar` block macro — AST transformation | Medium-high |
| `treenimph/runner.nim` | `run()` proc — CLI arg parsing, validate, render/export | Low |

### Modified modules

| Module | Change |
|---|---|
| `treenimph.nim` (root) | Add `export runner` so `import treenimph` gains `run()` |

---

## DSL Macro Implementation: Detailed Design

### Macro signature

```nim
macro grammar*(name: string, body: untyped): untyped =
```

The `body` parameter is `untyped`, meaning Nim passes the raw AST before any semantic analysis. This is essential — it allows the macro to accept bare identifiers that don't exist as Nim variables.

### AST transformation pipeline

The macro processes the body `nnkStmtList` in two passes:

**Pass 1: Categorize lines**
Walk each statement in the block and classify it as:
- `nnkLetSection` → `let` binding (track bound names, transform RHS)
- `nnkAsgn` where LHS is a reserved config name → grammar config
- `nnkAsgn` where LHS is an identifier → rule definition
- Anything else → compile-time error with helpful message

**Pass 2: Transform expressions**
For each rule body and config value, recursively rewrite the AST:

| Input AST node | Output |
|---|---|
| `nnkIdent "foo"` (not let-bound, not reserved) | `Ref("foo")` call |
| `nnkIdent "foo"` (let-bound) | Left as-is (variable reference) |
| `nnkStrLit "text"` | `Text("text")` call |
| `nnkCallStrLit` with `re` | `Regex("pattern")` call |
| `nnkBracket [a, b, c]` | `Sequence(transform(a), transform(b), transform(c))` call |
| `nnkInfix "\|" a b` | `Choice(...)` call (flattened) |
| `nnkInfix "@" name expr` | `Field("name", transform(expr))` call |
| `nnkPrefix "?" expr` | `Optional(transform(expr))` call |
| `nnkPrefix "*" expr` | `ZeroOrMore(transform(expr))` call |
| `nnkPrefix "+" expr` | `OneOrMore(transform(expr))` call |
| `nnkCall "prec_left" args` | `PrecLeft(level, transform(body))` call |
| `nnkCall "prec_right" args` | `PrecRight(level, transform(body))` call |
| `nnkCall "prec_dynamic" args` | `PrecDynamic(level, transform(body))` call |
| `nnkCall "prec" args` | `Prec(level, transform(body))` call |
| `nnkCall "token" args` | `Token(transform(body))` call |
| `nnkCall "immediate_token" args` | `ImmediateToken(transform(body))` call |
| `nnkCall "alias" args` | `Alias(...)` call |
| `nnkCall other_name args` | Passthrough: `other_name(transform(args)...)` |
| `nnkPar (expr)` | Unwrap parentheses, transform inner |

### Flattening chained operators

`a | b | c` parses as `nnkInfix("|", nnkInfix("|", a, b), c)` — left-associative tree. The transform must flatten this:

```
if node is nnkInfix "|":
  collect all leaves by walking left-child "|" chains
  emit Choice(leaf1, leaf2, leaf3, ...)
```

No flattening needed for `@` (it's always binary) or brackets (already flat by structure).

### Generated output

The macro emits a complete Nim program:

```nim
import treenimph
import treenimph/runner

# let bindings (transformed)
let value = Ref("_value")
let comma = Text(",")

# grammar construction
let grammar = mkGrammar(
  "json",
  extras = [Regex("\\s+")],
  rules = [
    mkRule("document", value),
    mkRule("_value", Choice(Ref("object"), Ref("array"), ...)),
    ...
  ],
)

# CLI runner
run(grammar)
```

### Error reporting

The macro should provide clear compile-time errors with line information:

```nim
# Use error("message", astNode) to report at the correct source line
if lhs.kind != nnkIdent:
  error("Expected rule name (identifier), got " & $lhs.kind, lhs)
```

Key error cases to handle:
- Non-identifier on left side of `=`
- `@` with non-identifier left operand
- Unknown config key that looks like a typo of a reserved name
- Empty grammar body

---

## Runner Implementation: Detailed Design

### Module: `treenimph/runner.nim`

```nim
proc run*(g: Grammar) =
  ## Entry point for grammar files. Validates, parses CLI args, dispatches.

  # 1. Validate (always)
  let diags = g.validate()
  # Print warnings to stderr
  # If errors, print and exit(1)

  # 2. Parse CLI args
  # --export <dir>    → exportGrammar with config
  # --summary         → echo g.summary()
  # --validate        → already done, exit(0)
  # --overwrite       → flag for export
  # --run-generate    → flag for export
  # (default)         → echo g.renderGrammarJs()

  # 3. Execute
```

This is straightforward procedural code. Uses `std/parseopt` for argument parsing.

### CLI interface

```
Usage: nim r grammar_file.nim [options]

Options:
  (no options)          Print grammar.js to stdout
  --export <dir>        Export full tree-sitter package to directory
  --summary             Print grammar summary
  --validate            Validate only (exit 0 = clean, exit 1 = errors)
  --overwrite           Allow overwriting existing files (with --export)
  --run-generate        Run tree-sitter generate after export (with --export)
  --no-query-stubs      Skip generating empty query stubs (with --export)
```

---

## Migration Path

### For existing users

The raw API (`import treenimph`) continues to work exactly as before. The DSL is opt-in via `import treenimph/dsl`.

### For examples

The three existing examples would be rewritten to use the DSL:

| Before | After |
|---|---|
| `import treenimph` | `import treenimph/dsl` |
| `mkRule("name", Sequence(Text("let"), ...))` | `name = ["let", ...]` |
| `grammar.validateOrRaise()` | (handled by macro) |
| `echo grammar.renderGrammarJs()` | (handled by macro) |

The old-style examples could be preserved in `examples/raw/` for reference.

---

## Implementation Order

### Phase 1: Runner (`treenimph/runner.nim`)
- Implement `run()` proc with CLI arg parsing
- Update `treenimph.nim` to export it
- Update examples to use `run(grammar)` instead of manual validate/echo
- This is independently useful even without the macro

### Phase 2: DSL macro (`treenimph/dsl.nim`)
- Implement the `grammar` block macro
- AST transformation for all expression types
- `let` binding tracking
- Config line recognition
- Operator flattening (`|` chains)
- Compile-time error reporting

### Phase 3: Update examples and tests
- Rewrite all examples using the DSL
- Add DSL-specific tests (macro expansion, error messages)
- Verify that DSL examples produce identical `grammar.js` output to raw API examples

### Phase 4: Documentation
- Document the DSL syntax in README
- Doc comments on macro and runner
- Examples as primary documentation

---

## Open Questions

### 1. Should `grammar` macro auto-import helpers?

Currently, using `delimitedList` or `balanced` inside the DSL requires that they be available in scope. Options:
- **A)** The DSL module re-exports helpers — `import treenimph/dsl` gives you everything
- **B)** Users import helpers separately if needed — `import treenimph/helpers`

Recommendation: **A** — the DSL should be batteries-included. One import, everything works.

### 2. How should `extras` brackets be distinguished from sequence brackets?

`extras = [re"\\s+"]` uses brackets for a list of extras, not a sequence. Since `extras` is a recognized config name, the macro handles it specially — the brackets are interpreted as a Nim array/seq, not as a Sequence constructor. The transformation still applies to the elements (so `re"\\s+"` becomes `Regex(...)`), but they're collected into a `seq[Expr]`, not wrapped in `Sequence()`.

This is unambiguous because config names are reserved.

### 3. Should `grammar` return the Grammar object or just run it?

Options:
- **A)** `grammar` emits both the grammar definition AND a `run()` call — the file is fully self-contained
- **B)** `grammar` returns a `Grammar` object that the user can `run()` manually: `run grammar "name": ...`
- **C)** Both: `grammar` defines + runs, but also provides a way to get the object for advanced use

Recommendation: **A** for simplicity. If users need the Grammar object for custom processing, they can use the raw API. The DSL is for the 90% case where you just want to define and output.

### 4. Naming: `@` for fields vs alternatives

`@` reads well for fields (`name@identifier`), but alternatives exist:
- `name@expr` — "name at expression" (proposed)
- `name:expr` — colon, more BNF-like but may conflict with Nim parsing in some contexts
- `name->expr` — arrow, readable but longer

Recommendation: **`@`** — it's a valid Nim operator, visually distinctive, and no parsing ambiguity.

### 5. Naming: `re"..."` or `regex"..."` or `r"..."`

Nim supports any identifier as a generalized string literal prefix. Options:
- `re"..."` — short, familiar from Python/Nim regex libraries
- `regex"..."` — explicit but verbose
- `r"..."` — very short but might be confused with raw strings

Recommendation: **`re"..."`** — it's the established convention in Nim's ecosystem.
