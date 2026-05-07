# TreeNimph Roadmap

**Date:** 2026-05-07 (revised)
**Current version:** 0.1.0 (MVP complete, post code-review refactor)
**Baseline commit:** `2bdbc53`

---

## Where We Are Now

TreeNimph's MVP is complete. The core pipeline works end-to-end: users define grammars as typed Nim objects, validate them, render `grammar.js`, and export standard Tree-sitter packages. The architecture follows the concept documents faithfully — object variants with constructor procs, five-layer internal structure (model → validation → rendering → export → helpers), and full compatibility with the Tree-sitter ecosystem.

### Current capabilities

- 14 expression types covering all Tree-sitter grammar constructs
- Comprehensive validation with structured diagnostics and "did you mean?" suggestions
- Clean, readable, deterministic `grammar.js` rendering
- Full package export (`grammar.js`, `package.json`, `tree-sitter.json`, query stubs, scanner passthrough)
- Optional `tree-sitter generate` invocation with output verification
- Query file passthrough (raw `.scm` content)
- File ownership protection (won't overwrite non-TreeNimph files)
- 82 tests, 3 example grammars, 4 composition helpers

### What's missing

The remaining work falls into five categories:
1. **Macro DSL and runner** — transform grammar files from "Nim programs that use a library" into native-feeling grammar definitions
2. **Proving the design at scale** — larger examples, round-trip tests
3. **Documentation and polish** — doc comments, README, publishing readiness
4. **Advanced validation** — reachability analysis, deeper semantic checks
5. **Query DSL** — the planned future layer for highlights, locals, injections, tags

---

## Milestone 1: Macro DSL and Runner

**Goal:** Make grammar files feel native — pure grammar definitions, not Nim programs with boilerplate.

**Concept document:** `V2_MACRO_REFACTOR_CONCEPT.md`

This is the highest-priority milestone. It directly addresses the core usability gap: grammar files today require ceremony (`Ref("name")`, `Text("let")`, `Sequence(...)`, `mkRule("name", ...)`, `grammar.validateOrRaise()`, `echo grammar.renderGrammarJs()`) that obscures the grammar definition itself.

### Target: what grammar files should look like

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

That's the entire file. No `mkRule`, no `Ref()`, no `Text()`, no trailing boilerplate.

### 1.1 — Runner module (`treenimph/runner.nim`)

Implement a `run(grammar)` proc that replaces the manual validate/echo/export pattern:

- Validates the grammar (prints warnings to stderr, raises on errors)
- Parses CLI arguments (`--export <dir>`, `--summary`, `--validate`)
- Defaults to printing `grammar.js` to stdout

This is independently useful even before the macro. Existing examples can immediately switch from:
```nim
grammar.validateOrRaise()
echo grammar.renderGrammarJs()
```
to:
```nim
run(grammar)
```

**Deliverable:** `src/treenimph/runner.nim`, updated `treenimph.nim` root module, updated examples.

### 1.2 — DSL macro (`treenimph/dsl.nim`)

Implement the `grammar` block macro that transforms DSL syntax into raw API calls. The macro:

1. Receives the grammar body as an `untyped` `nnkStmtList`
2. Categorizes each line (config, `let` binding, or rule)
3. Recursively transforms rule body expressions:
   - Bare identifiers → `Ref("name")` (unless `let`-bound)
   - String literals → `Text("...")`
   - `re"..."` → `Regex("...")`
   - `[a, b, c]` brackets → `Sequence(a, b, c)`
   - `a | b | c` → `Choice(a, b, c)` (flattened)
   - `?x` → `Optional(x)`
   - `*x` → `ZeroOrMore(x)`
   - `+x` → `OneOrMore(x)`
   - `name@expr` → `Field("name", expr)`
   - `prec_left(n, expr)`, `token(expr)`, etc. → recognized calls with transformed args
   - Unknown calls (helpers like `delimitedList`) → passthrough with transformed args
4. Recognizes reserved config names (`extras`, `word`, `conflicts`, `supertypes`, `inline`, `externals`, `scannerPath`, `queryFiles`)
5. Tracks `let`-bound names to avoid converting them to `Ref()` calls
6. Emits a complete program: grammar construction + `run()` call

The DSL module re-exports all of `treenimph` plus `runner` and `helpers`, so `import treenimph/dsl` is the only import needed.

**Deliverable:** `src/treenimph/dsl.nim`, DSL-specific tests.

### 1.3 — Rewrite examples using DSL

Convert all three examples (simple_lang, arithmetic, json_like) to use the DSL. Verify they produce identical `grammar.js` output to the raw API versions. Preserve the raw API versions in `examples/raw/` for reference.

**Deliverable:** Updated examples, comparison tests confirming output equivalence.

### Key design decisions (decided)

| Decision | Choice | Rationale |
|---|---|---|
| Sequence syntax | `[a, b, c]` brackets | Visual grouping, reads like a list of steps, no custom operator needed |
| Choice syntax | `a \| b \| c` infix | Standard BNF convention, Nim precedence works correctly |
| Field syntax | `name@expr` infix | Valid Nim operator, visually distinctive, no parsing ambiguity |
| Repetition syntax | `*x`, `+x`, `?x` prefix | Familiar regex/BNF conventions |
| Regex syntax | `re"..."` | Established Nim ecosystem convention |
| Runner behavior | Default prints grammar.js, CLI flags for export/summary/validate | Useful for both quick testing and production export |
| Core library changes | None — DSL is a pure transformation layer on top | Preserves stability, raw API remains available |

---

## Milestone 2: Prove at Scale

**Goal:** Demonstrate that the library (and the new DSL) works well for real-world grammars.

### 2.1 — Add a substantial example grammar (20-30 rules)

The concept review flagged that the largest example (json_like, 10 rules) doesn't stress-test verbosity or composition at realistic scale. Write this example using the DSL to validate the new authoring experience. The grammar should exercise:

- Multiple rule categories (statements, expressions, declarations, literals)
- Deep nesting and composition
- Helper usage (`delimitedList`, `balanced`, etc.)
- All grammar config sections (word, extras, supertypes, conflicts, inline, externals)
- Hidden rules, precedence at multiple levels, fields on most rules

**Candidate languages:** TOML, INI, a simplified Lua, a simplified CSS, or a calculator-with-statements language.

**Deliverable:** `examples/toml_like.nim` (or similar) — a 20-30 rule grammar using the DSL.

### 2.2 — Round-trip integration tests

Current tests validate + render but never actually run `tree-sitter generate` on the exported output. A round-trip test would:

1. Define a grammar in TreeNimph
2. Export to a temp directory with `runGenerate = true`
3. Confirm `tree-sitter generate` succeeds
4. Confirm `src/parser.c` and `src/node-types.json` exist
5. Optionally: use `tree-sitter parse` on sample source and verify the parse tree

**Deliverable:** `tests/test_roundtrip.nim` — at least 2-3 grammars exported and generated end-to-end.

### 2.3 — Evaluate and expand the helper library

After writing a 20-30 rule grammar with the DSL, audit which patterns were painful. Only add helpers that emerged as genuine pain points. Likely candidates:

- `commaSeparated(item)` — shortcut for `delimitedList(item, Text(","))`
- `parenthesized(expr)` / `bracketed(expr)` / `braced(expr)` — specializations of `balanced`
- `binaryOp(left, op, right, prec, assoc)` — common in expression grammars

**Deliverable:** 2-5 new helpers in `helpers.nim` with tests, driven by actual usage.

---

## Milestone 3: Documentation and Polish

**Goal:** Make the library ready for other people to use.

### 3.1 — Doc comments on all public procs and types

Every exported proc, type, and field should have a `##` doc comment. Priority files:

1. `model.nim` — all constructors, `Grammar`, `Rule`, `ExportConfig`, `QueryFiles`
2. `dsl.nim` — the `grammar` macro, DSL syntax reference
3. `runner.nim` — `run()`, CLI options
4. `validate.nim` — `validate`, `validateOrRaise`
5. `render_js.nim`, `render_package.nim`, `exporter.nim`, `helpers.nim`, `diagnostics.nim`

### 3.2 — README rewrite

The current README is a single line. Replace it with:

- Project description and tagline
- Quick-start example using the DSL
- Installation instructions (nimble)
- DSL syntax reference (operators, brackets, config)
- Raw API overview for advanced use cases
- Link to examples and Tree-sitter docs

### 3.3 — README.md stub generation on export

Export should generate a `README.md` stub in the output directory with the grammar name, a note that it was generated by TreeNimph, and basic usage pointers.

### 3.4 — `nim doc` generation

Set up `nimble docs` task to generate HTML API documentation from doc comments.

---

## Milestone 4: Advanced Validation

**Goal:** Move beyond structural checks into semantic analysis.

### 4.1 — Reachability analysis

BFS/DFS from the first rule through all `Ref` edges. Any rule not visited is unreachable. Emit as `dkWarning`.

### 4.2 — Self-referencing cycle detection

Detect rules that form left-recursive cycles without a base case. Emit as `dkWarning`.

### 4.3 — Duplicate literal detection

Detect `Text("keyword")` values appearing 3+ times across rules. Suggest centralizing into a shared variable (or `let` binding in the DSL).

### 4.4 — External ref validation

Check that externals don't shadow real rule names or have invalid identifiers.

---

## Milestone 5: Testing Depth

**Goal:** Harden the test suite to catch regressions and edge cases.

### 5.1 — Error message snapshot tests

Validation error messages are a user-facing API surface. Snapshot tests prevent accidental regressions.

### 5.2 — Comparison tests against hand-written grammars

Take 1-2 well-known Tree-sitter grammars (e.g., tree-sitter-json), translate into TreeNimph, and diff output.

### 5.3 — DSL-specific tests

- Macro expansion produces correct raw API calls
- DSL and raw API produce identical grammar.js for equivalent definitions
- Compile-time error messages for invalid DSL syntax are clear and point to correct lines
- `let` binding tracking works correctly (bound names don't become `Ref()`)
- Operator flattening (`|` chains) produces correct `Choice` arity

### 5.4 — Fuzz-style edge cases

Test grammars with very long rule names, unicode in text literals, empty grammar name, hundreds of rules, deeply nested expressions.

---

## Milestone 6: Query DSL

**Goal:** Move from raw query passthrough to a structured, composable, validated query authoring model.

This corresponds to Phases 3-5 of the query concept rollout. The current state (Phase 2 — raw passthrough) is sufficient for v1 users.

### 6.1 — Low-level query IR (Query Concept Phase 3)

Core query AST types: `QueryPattern`, `NodeMatch`, `FieldConstraint`, `ChildPattern`, `Capture`, `Predicate`, `Wildcard`, `AnchorPattern`, `QueryDocument`.

### 6.2 — Category-specific models (Query Concept Phase 4)

Ergonomic wrappers for highlights, tags, locals, and injections.

### 6.3 — Query validation against the grammar model

Cross-validate node type references, field constraints, and capture names against the grammar definition.

### 6.4 — Decide integrated vs. separate authoring (Query Concept Phase 5)

Path A (queries inside Grammar) vs Path B (separate files) vs both.

### 6.5 — Query rendering

Render query IR to standard `.scm` files with clean, readable S-expressions.

---

## Milestone 7: Ecosystem and Publishing

**Goal:** Make TreeNimph a proper, installable, CI-tested library.

### 7.1 — CI pipeline

GitHub Actions: run tests, `nim check`, round-trip integration tests, test against Nim 2.0.x and 2.2.x.

### 7.2 — Nimble package publishing

Verify nimble file, add license, tag release, register with Nim package index.

### 7.3 — Versioning strategy

| Version | Milestone |
|---|---|
| `0.2.0` | Milestone 1 (DSL + runner) |
| `0.3.0` | Milestone 2 (scale proof) + Milestone 3 (docs) |
| `0.4.0` | Milestone 4 (advanced validation) + Milestone 5 (testing depth) |
| `0.5.0` | Milestone 6 (query DSL) |
| `1.0.0` | Stable API, full documentation, CI, published package |

---

## Milestone 8: Future Extensions

Explicitly deferred. Only pursue based on real user demand.

- **Rule graph visualization** — DOT/Graphviz diagram of rule dependencies
- **Documentation generation** — human-readable grammar structure docs from Grammar objects
- **Linting recommendations** — suggest inlining, splitting, helper usage for large grammars
- **Source-location-aware validation** — track Nim source locations through the object graph via macros + `instantiationInfo()`

---

## Priority Order

1. **Milestone 1 (DSL + Runner)** — highest priority. This is the fundamental UX improvement that redefines what grammar files feel like. Everything else benefits from it.

2. **Milestone 2 (Prove at Scale)** — uses the DSL to validate both the library and the new authoring experience on a real grammar. Should follow immediately after Milestone 1.

3. **Milestone 3 (Documentation)** — needed before anyone else can use the library. The DSL changes the README and docs substantially.

4. **Milestone 5 (Testing Depth)** — should happen alongside Milestones 1-3. DSL-specific tests are critical.

5. **Milestone 4 (Advanced Validation)** — nice quality-of-life improvements, can be done incrementally.

6. **Milestone 7 (Ecosystem)** — blocking for adoption but not for development.

7. **Milestone 6 (Query DSL)** — biggest remaining feature. Only start after Milestones 1-3 are complete.

8. **Milestone 8 (Future Extensions)** — aspirational.

---

## Decision Log

Decisions already made (from concept review + implementation + DSL design):

| Decision | Choice | Rationale |
|---|---|---|
| Expression hierarchy | Object variants + constructor procs | Idiomatic Nim, exhaustive matching, clean API surface |
| Precedence representation | Single type + assoc field (Option B) | Fewer types, maps to tree-sitter's model |
| Export module naming | `exporter.nim` | `export` is a Nim reserved word |
| v1 error reporting | Grammar-domain locations (rule names) | Pragmatic; source locations deferred |
| Query v1 support | Raw passthrough (`QueryFiles`) | Doesn't foreclose future DSL |
| Helper library size | Minimal (4 helpers) | Grow based on real usage, not speculation |
| DSL sequence syntax | `[a, b, c]` brackets | Visual grouping, no custom operator, Nim `nnkBracket` |
| DSL choice syntax | `a \| b \| c` infix | Standard BNF, correct Nim precedence |
| DSL field syntax | `name@expr` infix | Valid Nim operator, distinctive, unambiguous |
| DSL repetition syntax | `*x`, `+x`, `?x` prefix | Familiar regex/BNF |
| DSL regex syntax | `re"..."` | Nim ecosystem convention |
| DSL architecture | Pure transformation layer, core library unchanged | Stability, backwards compatibility |
| DSL import model | `import treenimph/dsl` re-exports everything | Batteries-included, one import |
| Grammar macro behavior | Defines grammar + calls `run()` | Self-contained grammar files, no trailing boilerplate |

Decisions still pending:

| Decision | Options | When to Decide |
|---|---|---|
| Query authoring path | Path A (integrated) vs Path B (separate) vs both | After Milestone 6.1-6.2 prototyping |
| README.md stub content | Minimal vs detailed template | Milestone 3.3 |
| CI platform | GitHub Actions vs other | Milestone 7.1 |
| Nim version support floor | 2.0.0 vs 2.2.0 | Milestone 7.1 (test both first) |
