# TreeNimph

## Concept

TreeNimph is a Nim library for authoring Tree-sitter grammars in a **class-like, composable, strongly-structured style** that feels familiar to Python developers.

Instead of writing `grammar.js` directly, grammar authors define a grammar as a graph of typed Nim objects such as `Grammar`, `Rule`, `Sequence`, `Choice`, `Field`, `Text`, and `Ref`. TreeNimph then exports a standard Tree-sitter grammar package containing a generated `grammar.js` and the expected package metadata and directory layout. Optionally, TreeNimph can invoke the official `tree-sitter generate` command so the export directory is immediately usable by the wider Tree-sitter ecosystem.

TreeNimph is **not** a parser generator, and it does **not** replace Tree-sitter. Its role is to make grammar authoring dramatically more ergonomic, composable, validated, and maintainable while preserving full compatibility with the existing Tree-sitter toolchain.

---

## Tagline

**TreeNimph lets users write Tree-sitter grammars as composable Nim objects and export them as standard Tree-sitter packages.**

---

## Problem Statement

Tree-sitter grammar authoring is powerful, but its default authoring experience is centered on a JavaScript DSL. That creates a few recurring problems for developers who would prefer a more structured and model-driven approach:

- The grammar is authored in JavaScript even when the author’s preferred language is not JavaScript.
- The DSL encourages a fairly expression-heavy style rather than a strongly object-based one.
- Reusable grammar fragments are possible, but the overall style is not especially aligned with the way Python developers think about validated structured models.
- The syntax relies on conventions like `$.identifier` that feel natural in Tree-sitter’s JS DSL but less natural to developers who prefer explicit object construction.
- Validation opportunities exist, but they are not surfaced through a strongly typed authoring model.
- There is friction between “write something quickly” and “maintain a large grammar cleanly over time.”

TreeNimph addresses these issues by moving grammar authoring into Nim while preserving the standard Tree-sitter output and workflow.

---

## Non-Goals

TreeNimph deliberately does **not** aim to do the following:

- Reimplement the Tree-sitter parser generator.
- Replace `tree-sitter generate`.
- Introduce a custom parser backend.
- Require downstream tools to understand Nim.
- Create multiple first-class authoring syntaxes.
- Make grammar authors reason about JS-specific Tree-sitter DSL conventions.
- Hide Tree-sitter concepts behind a radically different abstraction.

TreeNimph should remain a **frontend authoring layer** over the normal Tree-sitter ecosystem.

---

## Core Design Goals

### 1. Single Authoring Style

TreeNimph should provide **one primary way** to write grammars.

There should not be a split between a “friendly API” and a “compatibility API.” The library should have a single, coherent, class-like design centered on typed objects. Any internal aliases or conveniences should not fracture the public mental model.

### 2. Class-Like and Structured

The grammar should feel like a set of structured model instances rather than an embedded symbolic DSL.

Authors should primarily compose values such as:

- `Grammar`
- `Rule`
- `Ref`
- `Text`
- `Regex`
- `Sequence`
- `Choice`
- `Optional`
- `ZeroOrMore`
- `OneOrMore`
- `Field`
- `Alias`
- `Token`
- precedence wrapper types

### 3. Composable by Default

Reusable building blocks should be a normal, encouraged pattern.

Users should be able to define intermediate grammar fragments once and reuse them elsewhere in the file through ordinary Nim variables and helper procs.

### 4. Familiar to Python Developers

Even though TreeNimph is written in Nim, it should feel familiar to people who think in terms of Python classes, dataclasses, and Pydantic-style structured models.

That means:

- explicit names instead of symbolic shorthands
- object construction instead of magical DSL punctuation
- named fields
- reusable model fragments
- clear validation errors
- inspectable representations

### 5. Strictly Compatible with Tree-sitter

TreeNimph should emit a standard Tree-sitter package layout and generated `grammar.js` so that downstream tools work exactly as they would for a hand-written grammar.

### 6. Clear Boundaries

The compatibility boundary should be the generated `grammar.js` and standard package structure. Downstream consumers should not need to know TreeNimph exists.

---

## Product Definition

TreeNimph is best described as:

> A Nim library for authoring Tree-sitter grammars as composable typed objects and exporting them as standard Tree-sitter grammar packages.

That definition implies three responsibilities:

1. Provide a structured Nim authoring model for grammars.
2. Validate that model before export.
3. Emit standard Tree-sitter package files and optionally invoke the official generator.

---

## Authoring Model

The core authoring model is a graph of typed objects.

### `Grammar`

Represents the entire grammar package concept.

Suggested responsibilities:

- store grammar metadata such as the name
- store all rule definitions
- store extras, conflicts, supertypes, inline rules, externals, and package-level configuration
- validate internal consistency
- render itself to `grammar.js`
- export itself to a package directory

### `Rule`

Represents a named grammar rule.

Suggested fields:

- `name`
- `body`
- optional metadata used during rendering or validation

### `Expr`

A shared base concept for all grammar expressions.

All concrete expression types should derive from or conform to a common expression model.

### Concrete Expression Types

The public API should center on explicit, class-like expression types:

- `Ref(name = "identifier")`
- `Text(value = "=")`
- `Regex(pattern = @"\s+")`
- `Sequence(items = @[...])`
- `Choice(items = @[...])`
- `Optional(item = ...)`
- `ZeroOrMore(item = ...)`
- `OneOrMore(item = ...)`
- `Field(name = "target", expr = ...)`
- `Alias(name = "name", expr = ...)`
- `Token(expr = ...)`
- precedence wrapper types such as `LeftPrecedence`, `RightPrecedence`, or `DynamicPrecedence`

This keeps the system explicit and readable while allowing composition through ordinary Nim values.

---

## Example Authoring Style

The intended style should look something like this:

```nim
let
  Identifier = Ref(name = "identifier")
  Expression = Ref(name = "expression")
  Equals = Text(value = "=")

  AssignmentBody = Sequence(items = @[
    Field(name = "target", expr = Identifier),
    Equals,
    Field(name = "value", expr = Expression),
  ])

let grammar = Grammar(
  name = "mylang",
  rules = @[
    Rule(name = "assignment", body = AssignmentBody),
    Rule(name = "statement", body = Choice(items = @[
      Ref(name = "assignment"),
      Ref(name = "expression"),
    ])),
  ]
)

grammar.export("dist/tree-sitter-mylang")
```

This is the defining stylistic goal for TreeNimph:

- explicit object construction
- normal host-language composition
- one uniform grammar style
- no `$.identifier`
- no JavaScript-first syntax assumptions

---

## Composability Model

Composability is a primary feature, not an incidental convenience.

TreeNimph should support three levels of composition.

### 1. Reusable Expression Values

Authors should be able to assign expressions to Nim variables and reuse them naturally.

Example:

```nim
let
  Comma = Text(value = ",")
  Identifier = Ref(name = "identifier")
  Parameter = Ref(name = "parameter")
```

This is the simplest and most important form of composition.

### 2. Reusable Composite Fragments

Authors should be able to assemble larger expression fragments and plug them into multiple rules.

Example:

```nim
let
  AssignmentCore = Sequence(items = @[
    Field(name = "target", expr = Ref(name = "identifier")),
    Text(value = "="),
    Field(name = "value", expr = Ref(name = "expression")),
  ])
```

### 3. Reusable Helper Constructors

Authors or library code should be able to define helper procs that construct common patterns.

Example:

```nim
proc DelimitedList(item: Expr, separator: Expr, allowTrailing = false): Expr =
  if allowTrailing:
    Sequence(items = @[
      item,
      ZeroOrMore(item = Sequence(items = @[separator, item])),
      Optional(item = separator),
    ])
  else:
    Sequence(items = @[
      item,
      ZeroOrMore(item = Sequence(items = @[separator, item])),
    ])
```

This enables a highly reusable, Python-friendly composition style without inventing a second DSL.

---

## Why the Class-Like Style Matters

The chosen style is not just an aesthetic preference. It affects how the library scales.

### Benefits

- Easier for Python developers to read and reason about.
- Easier to validate because the grammar is a structured object graph.
- Easier to refactor because reusable fragments are plain host-language values.
- Easier to introspect because expressions can be inspected, serialized, summarized, or debug-rendered.
- Easier to teach because authors learn a finite set of object types instead of a symbolic embedded language.
- Easier to evolve because new expression types can be introduced in a consistent way.

### Tradeoff

The class-like style is slightly more verbose than Tree-sitter’s native JavaScript DSL. TreeNimph intentionally accepts that tradeoff in exchange for clarity, structure, and composability.

---

## Naming Philosophy

TreeNimph should use names that feel explicit and readable rather than symbolic and DSL-heavy.

### Good Names

- `Ref`
- `Text`
- `Regex`
- `Sequence`
- `Choice`
- `Optional`
- `ZeroOrMore`
- `OneOrMore`
- `Field`
- `Alias`
- `Token`
- `Grammar`
- `Rule`

### Avoided Styles

- `$.identifier`
- JS-centric callback conventions
- punctuation-heavy shortcuts
- public symbolic shorthands that become the “real” way to write grammars

The public style should feel like constructing a set of strongly-typed schema objects.

---

## Tree-sitter Compatibility Strategy

TreeNimph should preserve perfect compatibility with the existing ecosystem by treating the generated `grammar.js` as the compatibility boundary.

### Why This Boundary Matters

It ensures:

- downstream tools do not need to understand Nim
- generated grammar repositories look normal
- the official Tree-sitter CLI remains the parser-generation source of truth
- debugging remains possible by reading emitted JS
- users can compare emitted output against hand-written Tree-sitter grammars

### Export Flow

The high-level export flow should be:

1. author creates a `Grammar` object in Nim
2. TreeNimph validates the grammar model
3. TreeNimph emits a canonical `grammar.js`
4. TreeNimph writes standard package metadata and directory scaffolding
5. optionally, TreeNimph runs `tree-sitter generate`
6. the export directory becomes a standard Tree-sitter grammar package

---

## Expected Export Directory

A typical TreeNimph export directory should resemble a normal Tree-sitter grammar package.

Suggested structure:

```text
<export-dir>/
  grammar.js
  package.json
  tree-sitter.json
  README.md
  queries/
    highlights.scm
    injections.scm
    tags.scm
  src/
    parser.c          # produced by tree-sitter generate
    node-types.json   # produced by tree-sitter generate
    scanner.c         # optional passthrough
```

Depending on future goals, additional files may also be generated, but the export should always look conventional.

---

## Scope of TreeNimph-Generated Files

### Files TreeNimph Should Generate Directly

- `grammar.js`
- `package.json`
- `tree-sitter.json`
- `README.md` stub
- `queries/highlights.scm` stub
- `queries/injections.scm` stub
- `queries/tags.scm` stub
- any optional package scaffolding required for a polished repo export

### Files TreeNimph Should Prefer Not to Generate Directly

These should come from the official Tree-sitter toolchain:

- `src/parser.c`
- `src/node-types.json`
- any other files normally produced by `tree-sitter generate`

This division is central to TreeNimph’s philosophy.

---

## Validation Model

Validation is one of the biggest reasons TreeNimph exists.

Since the grammar is represented as a structured object graph, TreeNimph should perform strong pre-export validation.

### Core Validation Checks

- duplicate rule names
- undefined `Ref` targets
- empty `Choice`
- empty `Sequence`
- invalid field names
- invalid alias names
- precedence wrappers used incorrectly
- invalid extras, conflicts, supertypes, inline rules, or externals references
- malformed export configuration
- missing optional passthrough files when explicitly configured

### Optional Higher-Level Checks

Over time, TreeNimph may add stronger semantic checks such as:

- suspicious self-references
- accidental unreachability of rules
- likely typos with suggestion output
- repeated literal patterns that should be centralized
- warnings for fragments reused in semantically odd ways

### Error Philosophy

Validation errors should be:

- specific
- structured
- easy to locate
- phrased in domain language the user understands

Examples:

- `Unknown rule reference: "identifer" in rule "assignment"`
- `Duplicate rule name: "expression"`
- `Choice must contain at least one item`
- `Field name "target value" is invalid`

If feasible, error messages should also provide “did you mean” suggestions.

---

## Introspection and Debuggability

A class-like design opens useful debugging possibilities. TreeNimph should expose them.

Suggested capabilities:

- render the grammar object as JSON-like debug output
- render generated `grammar.js` without exporting
- produce a summary of defined rules and references
- print or inspect a normalized expression tree
- run validation independently of export

Possible API examples:

```nim
let js = grammar.renderGrammarJs()
let report = grammar.validate()
echo grammar.summary()
```

These features help reinforce the model-driven design.

---

## Public API Shape

The public API should be minimal, coherent, and centered on a small set of concepts.

### Core Types

- `Grammar`
- `Rule`
- `Expr`
- expression subclasses or tagged variants
- export configuration types
- validation result types

### Core Operations

- construct grammar objects
- validate grammar objects
- render `grammar.js`
- export package structure
- optionally run `tree-sitter generate`

### Example

```nim
let grammar = Grammar(
  name = "mylang",
  rules = @[
    Rule(
      name = "assignment",
      body = Sequence(items = @[
        Field(name = "target", expr = Ref(name = "identifier")),
        Text(value = "="),
        Field(name = "value", expr = Ref(name = "expression")),
      ])
    )
  ]
)

grammar.validateOrRaise()
let js = grammar.renderGrammarJs()
grammar.export("dist/tree-sitter-mylang")
```

---

## Internal Architecture

Internally, TreeNimph should be organized around five layers.

### 1. Core IR / Model Layer

Defines the canonical in-memory representation of grammar objects.

Responsibilities:

- type definitions
- normalization helpers
- basic invariants

### 2. Validation Layer

Traverses the model to perform structural and semantic checks.

Responsibilities:

- duplicate detection
- reference resolution
- export config validation
- diagnostic formatting

### 3. Rendering Layer

Converts the model into emitted source files.

Responsibilities:

- `grammar.js` generation
- `package.json` generation
- `tree-sitter.json` generation
- query stub rendering
- README stub rendering

### 4. Export Layer

Writes files to disk and manages export behavior.

Responsibilities:

- create directories
- write generated files
- copy optional passthrough assets such as `scanner.c`
- optionally invoke `tree-sitter generate`
- verify expected outputs exist after generation

### 5. Helper / Composition Layer

Provides reusable library-level constructors for common patterns.

Responsibilities:

- list patterns
- delimited lists
- balanced group helpers
- common tokenization wrappers

This layer should remain additive and not introduce a second public grammar style.

---

## Expression Model Recommendations

The expression model should balance explicitness with enough coverage for normal Tree-sitter use cases.

### Essential Expression Types for v1

- `Ref`
- `Text`
- `Regex`
- `Sequence`
- `Choice`
- `Optional`
- `ZeroOrMore`
- `OneOrMore`
- `Field`
- `Token`
- `Alias`
- precedence wrappers

### Nice Additions After v1

- convenience list helpers
- wrappers for Tree-sitter extras/conflicts definitions
- richer export metadata models
- debug pretty-printers
- source-location-aware validation if practical

The v1 set should remain intentionally tight.

---

## Precedence Representation

Precedence should also follow the class-like design.

Rather than mirroring JS member-call style such as `prec.left(...)`, TreeNimph should expose precedence through explicit wrapper objects.

Possible approaches:

### Option A: Separate Types

- `LeftPrecedence(level = 10, expr = ...)`
- `RightPrecedence(level = 20, expr = ...)`
- `DynamicPrecedence(level = 5, expr = ...)`
- `PlainPrecedence(level = 3, expr = ...)`

### Option B: Single Type with Mode Field

- `Precedence(level = 10, assoc = Left, expr = ...)`

Option A is slightly more explicit and probably fits the class-like design best.

---

## Scanner Support

TreeNimph should keep scanner support minimal and pragmatic.

### v1 Approach

- allow the user to pass a path to an existing `scanner.c`
- copy that file into `src/scanner.c` during export
- validate that the file exists when configured

### Non-Goals for v1

- no Nim-native scanner DSL
- no scanner code generation
- no abstraction that hides how Tree-sitter external scanners actually work

This keeps TreeNimph aligned with its frontend-only role.

---

## Export Configuration

Export should be configurable, but not excessively open-ended.

Suggested configuration knobs:

- output directory
- whether to overwrite existing files
- whether to invoke `tree-sitter generate`
- optional path to `scanner.c`
- whether to scaffold query files
- package naming configuration
- whether to emit README and metadata stubs

Possible example:

```nim
let config = ExportConfig(
  outDir = "dist/tree-sitter-mylang",
  runGenerate = true,
  scannerPath = some("scanner.c"),
  writeQueryStubs = true,
)

grammar.export(config)
```

---

## Repository Layout for TreeNimph Itself

Suggested library structure:

```text
treenimph/
  src/
    treenimph.nim
    model.nim
    validate.nim
    render_js.nim
    render_package.nim
    export.nim
    helpers.nim
    diagnostics.nim
  tests/
    test_model.nim
    test_validate.nim
    test_render_js.nim
    test_export.nim
    test_examples.nim
  examples/
    arithmetic.nim
    json_like.nim
    simple_lang.nim
  docs/
    CONCEPT.md
```

This keeps the architecture easy to understand.

---

## Development Plan

A sensible implementation order for TreeNimph is:

### Phase 1: Core Model

- define the grammar and expression types
- support object construction cleanly
- ensure expressions can be composed naturally

### Phase 2: Validation

- implement name and reference validation
- implement basic structural checks
- establish diagnostic formatting conventions

### Phase 3: `grammar.js` Rendering

- map the object model to canonical Tree-sitter DSL output
- ensure generated JS is stable and readable
- add snapshot tests for emitted output

### Phase 4: Package Export

- write package metadata and scaffolding
- create output directory layout
- support optional query stubs and scanner passthrough

### Phase 5: Toolchain Integration

- optionally invoke `tree-sitter generate`
- check for successful outputs
- provide actionable error messages when the external tool fails

### Phase 6: Polish

- add examples
- add helper constructors
- improve diagnostics and summaries
- refine README and package templates

---

## Testing Strategy

TreeNimph should be tested at multiple levels.

### Unit Tests

- model construction
- expression composition
- validation rules
- renderer output

### Snapshot Tests

- emitted `grammar.js`
- emitted package files
- validation error formatting

### Integration Tests

- export a sample grammar
- run `tree-sitter generate`
- verify expected files exist
- verify generated grammar package is structurally normal

### Example Grammars

Maintain a small set of example grammars to continuously exercise the public API.

---

## Design Principles for Rendered `grammar.js`

The generated `grammar.js` should be:

- deterministic
- readable
- conventionally formatted
- minimally surprising
- easy to diff

Even though users are not expected to author JS directly, the generated output should still be pleasant to inspect.

This matters for debugging and trust.

---

## Future Extensions

These are plausible future additions, but should not shape the initial scope too much.

### Possible Future Features

- richer helper library for common grammar patterns
- better diagnostics with source-origin tracking
- rule graph visualization
- documentation generation from grammar objects
- linting recommendations for large grammars
- integration helpers for publishing generated grammar packages

### Features to Avoid Unless Truly Needed

- macro-heavy alternate authoring syntax
- multiple first-class DSL styles
- a new parser generation backend
- a Nim-native scanner abstraction that obscures Tree-sitter expectations

TreeNimph should stay disciplined about its identity.

---

## Risks and Tradeoffs

### 1. Verbosity

The class-like API is more verbose than native Tree-sitter JS.

Mitigation:

- lean into composition
- provide good helper constructors
- keep object names clean and unsurprising

### 2. Mapping Coverage

Tree-sitter’s grammar DSL has nuances that must be represented correctly.

Mitigation:

- design the IR around actual Tree-sitter concepts
- add rendering tests against known examples
- keep the compatibility boundary explicit

### 3. Over-Abstraction

There is a risk of making the model feel too distant from Tree-sitter.

Mitigation:

- preserve Tree-sitter semantics closely
- keep the object names aligned with recognizable concepts
- render canonical output that users can compare to normal grammars

### 4. Fragment Misuse

Composability makes reuse easy, but some reused fragments may not make semantic sense in every context.

Mitigation:

- provide strong validation
- add targeted warnings over time
- keep expression objects explicit rather than magical

---

## Why TreeNimph Should Exist

TreeNimph fills a very specific gap:

- It preserves the standard Tree-sitter ecosystem.
- It removes JavaScript from the authoring experience.
- It replaces symbolic grammar writing with structured object composition.
- It gives Python-oriented developers a much more familiar mental model.
- It makes large grammars easier to validate, debug, and maintain.

It is not trying to become “Tree-sitter, but different.”

It is trying to become:

> the best way for Nim and Python-minded developers to author standard Tree-sitter grammars.

---

## Final Summary

TreeNimph is a Nim library for writing Tree-sitter grammars in a single, class-like, composable style.

Users define grammars as typed object graphs made of `Grammar`, `Rule`, and explicit expression types like `Sequence`, `Choice`, `Ref`, `Text`, and `Field`. Reusable grammar fragments are composed naturally through Nim variables and helper procs. TreeNimph validates the resulting model, renders a canonical `grammar.js`, scaffolds a normal Tree-sitter package layout, and can optionally invoke the official Tree-sitter generator.

The defining principles are:

- one authoring style
- class-like structure
- composability by default
- Python-friendly ergonomics
- strict Tree-sitter compatibility
- no custom parser backend

That is the concept.
