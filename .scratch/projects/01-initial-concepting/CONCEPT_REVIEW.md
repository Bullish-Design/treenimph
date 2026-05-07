# TreeNimph Concept Review

## Overview

This review covers the two concept documents: `initial_treenimph_concept.md` (the core grammar authoring library) and `QUERY_CONCEPT.md` (future query support). The review evaluates the design on its own terms, identifies strengths, surfaces concerns, and offers recommendations.

---

## Executive Summary

TreeNimph is a well-scoped, clearly motivated library concept. It targets a real ergonomic gap in Tree-sitter grammar authoring by replacing JavaScript DSL authoring with composable Nim object construction. The concept is disciplined about what it is and what it is not. The compatibility boundary (generated `grammar.js`) is the right abstraction seam. The query concept is appropriately deferred but thoughtfully explored.

The main risks are: (1) the verbosity tradeoff may be steeper than expected for real-world grammars, (2) Nim's object variant system needs careful design to avoid ergonomic friction in the expression model, and (3) the "familiar to Python developers" framing creates expectations that Nim's type system may not naturally fulfill without deliberate API design work.

---

## What the Library Is

TreeNimph is a **frontend authoring layer** for Tree-sitter grammars. Users define grammars as typed Nim object graphs (`Grammar`, `Rule`, `Sequence`, `Choice`, `Ref`, `Text`, `Field`, etc.) and export them as standard Tree-sitter packages containing a generated `grammar.js` and conventional directory layout. TreeNimph validates the grammar model before export and can optionally invoke `tree-sitter generate` to produce the final parser artifacts.

TreeNimph is **not** a parser generator, does **not** replace Tree-sitter, and does **not** require downstream consumers to know Nim exists.

---

## Strengths

### 1. Clear Identity and Boundaries

The concept is unusually disciplined about scope. The non-goals section is specific and honest. The compatibility boundary (`grammar.js` as the contract) is the correct architectural decision — it means TreeNimph adds value without creating ecosystem fragmentation. This is rare in library design documents and should be preserved.

### 2. The Composability Model Is the Real Value Proposition

The three levels of composition (reusable expression values, composite fragments, helper constructor procs) are the strongest part of the design. Tree-sitter's native JS DSL makes reuse possible but not ergonomic. TreeNimph makes reuse the natural, default way to work. The `DelimitedList` helper example is a compelling illustration — this kind of pattern is genuinely painful to maintain in raw `grammar.js`.

### 3. Validation as a First-Class Feature

Catching errors like undefined `Ref` targets, duplicate rule names, empty `Choice`/`Sequence`, and invalid field names **before** running `tree-sitter generate` is a meaningful improvement. Tree-sitter's own error messages when `generate` fails on a malformed grammar are often cryptic. Moving validation earlier and making it domain-aware is a strong selling point.

### 4. Sensible Phased Development Plan

The six-phase plan (Core Model → Validation → Rendering → Export → Toolchain Integration → Polish) is well-ordered. Each phase produces testable, demonstrable output. The decision to defer scanner DSL support and query authoring to future work is correct.

### 5. The Query Concept Is Appropriately Deferred

The query document is thorough and shows genuine understanding of Tree-sitter's query ecosystem. The decision to keep it out of v1 is right. The exploration of Path A vs. Path B is useful forward planning that will prevent the grammar model from accidentally foreclosing future query integration.

---

## Concerns

### 1. The "Familiar to Python Developers" Framing Is Aspirational, Not Automatic

The concept repeatedly frames the design as "Python-friendly" and targets developers who "think in terms of Python classes, dataclasses, and Pydantic-style structured models." This is a valid design aspiration, but Nim's type system does not naturally produce Pydantic-like ergonomics without deliberate work.

**Specific friction points:**

- **Object variants vs. inheritance:** Nim's idiomatic approach to expression hierarchies is `object variants` (tagged unions via `case` discriminators). These are powerful but look and feel nothing like Python class hierarchies. A Python developer expecting `class Sequence(Expr)` will encounter `ExprKind = enum; Expr = object; case kind: ExprKind` instead. The concept document is ambiguous about whether `Expr` is a base type with subtypes or a variant — this decision has major API ergonomics implications.

- **Ref types and value semantics:** Nim objects are value types by default. An expression tree where `Sequence` contains `@[Expr]` requires either `ref` objects or boxing. If `Expr` is a variant object, it can be stored by value in sequences, but nested expressions (e.g., `Field` containing an `Expr` which is itself a `Sequence`) require `ref` to avoid infinite-size types. This is a well-known Nim design point that the concept should address explicitly.

- **Named construction syntax:** Nim does support `Type(field = value)` construction, which maps well to the concept examples. But Nim does not have keyword-only arguments, default validation, or post-init hooks the way Python dataclasses/Pydantic do. Validation must be called explicitly or wrapped in constructor procs.

**Recommendation:** The concept should either (a) specify the Nim-level representation strategy for the expression hierarchy (object variants vs. ref inheritance vs. a hybrid approach), or (b) explicitly flag this as a critical Phase 1 design decision. The "Python-friendly" framing should be treated as a UX goal to validate against the actual Nim implementation, not assumed to follow automatically from the object-construction syntax.

### 2. Verbosity May Be Steeper Than Acknowledged

The concept acknowledges that the class-like style is "slightly more verbose" than Tree-sitter's native JS DSL. For small examples like the assignment rule, this is true. For a real grammar like Python, TypeScript, or even a moderately complex config language, the difference may be substantial.

**Concrete comparison:**

Tree-sitter JS:
```js
assignment: $ => seq(
  field('target', $.identifier),
  '=',
  field('value', $.expression)
)
```

TreeNimph Nim:
```nim
Rule(name = "assignment", body = Sequence(items = @[
  Field(name = "target", expr = Ref(name = "identifier")),
  Text(value = "="),
  Field(name = "value", expr = Ref(name = "expression")),
]))
```

The TreeNimph version is roughly **2-3x longer** in character count and introduces significantly more syntactic noise (`name =`, `items = @[`, `expr =`, `value =`). For a grammar with 50-200 rules, this compounds. The composability features help offset this for repeated patterns, but one-off rules — which are common — pay the full verbosity cost every time.

**Recommendation:** The concept should include at least one realistic medium-complexity grammar example (20-30 rules) to honestly evaluate the verbosity tradeoff at scale. Consider whether lightweight convenience constructors (not a second DSL, but shorter proc signatures) should be part of the v1 public API rather than deferred to the helper layer. For example:

```nim
# Full explicit form
Field(name = "target", expr = Ref(name = "identifier"))

# Possible convenience (still one authoring style, just shorter)
field("target", ref("identifier"))
```

The concept's prohibition against "public symbolic shorthands that become the real way to write grammars" is wise, but there is a meaningful difference between symbolic shorthands and ergonomic proc wrappers.

### 3. The `@[]` Literal Tax

Nim sequences require `@[]` syntax for construction. This appears throughout the concept examples and adds visual noise:

```nim
Sequence(items = @[
  Field(name = "target", expr = Ref(name = "identifier")),
  Text(value = "="),
  Field(name = "value", expr = Ref(name = "expression")),
])
```

For `Sequence`, `Choice`, and `Grammar.rules`, this is unavoidable with raw Nim sequences. However, it could be mitigated with variadic constructors:

```nim
proc Sequence(items: varargs[Expr]): Expr = ...
```

This would allow:
```nim
Sequence(
  Field(name = "target", expr = Ref(name = "identifier")),
  Text(value = "="),
  Field(name = "value", expr = Ref(name = "expression")),
)
```

**Recommendation:** Evaluate whether variadic constructors for `Sequence`, `Choice`, and other list-bearing types should be part of the core API. This is not a second authoring style — it is standard Nim API design for reducing boilerplate.

### 4. Precedence Design Needs a Decision, Not Two Options

The concept presents two options for precedence representation (separate types vs. single type with mode field) and tentatively favors Option A. This is a core API surface that should be decided, not left open.

**Analysis:**

- **Option A** (separate types: `LeftPrecedence`, `RightPrecedence`, etc.) is more explicit but adds 3-4 more expression types to the hierarchy. If using object variants, each one needs a variant arm. If using ref inheritance, each one needs a subtype.

- **Option B** (single `Precedence` type with an `assoc` field) is more compact and maps more directly to Tree-sitter's internal representation, where precedence is a single concept with an associativity attribute.

- Tree-sitter itself treats precedence as `prec(n, rule)`, `prec.left(n, rule)`, `prec.right(n, rule)`, and `prec.dynamic(n, rule)` — four variants of one concept. This maps more naturally to Option B.

**Recommendation:** Choose Option B. It reduces the type count, maps more directly to Tree-sitter's own model, and avoids proliferating variant arms or subtypes. The `assoc` field makes the associativity explicit without requiring users to remember four separate type names.

### 5. Export Directory Ownership Semantics Are Underspecified

The concept describes the export directory structure but does not address:

- **Incremental export:** Does `grammar.export(...)` always overwrite the entire directory? What if the user has hand-edited `queries/highlights.scm` and re-exports? Are generated files marked as generated (e.g., with a comment header)?
- **Conflict with existing files:** If the export directory already contains a `grammar.js` from a previous run or a different source, what happens?
- **Git-friendliness:** Should the export produce deterministic output so that `git diff` shows only meaningful changes between grammar versions?

**Recommendation:** The concept should specify that:
1. Generated files include a "do not edit — generated by TreeNimph" header comment.
2. The export operation is idempotent and deterministic (same grammar model → same output bytes).
3. There is a clear policy for user-authored files in the export directory (e.g., TreeNimph only writes files it owns, never overwrites files it does not recognize).

### 6. The Helper Layer Boundary Is Vague

The concept describes a "Helper / Composition Layer" with patterns like `DelimitedList`, balanced groups, and common tokenization wrappers. It says this layer "should remain additive and not introduce a second public grammar style."

This is the right principle, but the boundary is hard to enforce. Once helpers like `DelimitedList` exist, they become the idiomatic way to express those patterns. Downstream users will build mental models around them. If the helpers have inconsistent signatures, surprising behaviors, or are incomplete, they become a source of frustration rather than convenience.

**Recommendation:** The v1 helper layer should be minimal and opinionated. Start with 3-5 helpers that cover genuinely common patterns (delimited list, optional trailing separator, balanced pair). Each helper should have a single clear signature and produce a standard `Expr` — no special types, no configuration explosion. Grow the helper set conservatively based on real usage.

### 7. Error Reporting Needs Source Location Strategy

The concept's validation error examples are clear and well-phrased:

```
Unknown rule reference: "identifer" in rule "assignment"
Duplicate rule name: "expression"
```

But these errors reference rule names, not source locations. In a 200-rule grammar defined across multiple Nim files, knowing that the error is "in rule assignment" is helpful but not sufficient. Users will want to know *where in their Nim source* the problem is.

Nim does not automatically track source locations for object construction. If TreeNimph wants source-aware errors, it needs to either:
1. Use macros to capture `instantiationInfo()` at construction time.
2. Accept that errors reference grammar-domain locations (rule names, expression paths) rather than Nim source locations.
3. Provide a debug mode that serializes the grammar model with enough context to locate problems.

**Recommendation:** For v1, option (2) is pragmatic and sufficient. Grammar-domain error locations (rule name + expression path within the rule) are good enough for most use cases. Source location tracking is a genuine "nice addition after v1" as the concept already notes, but the concept should explicitly choose option (2) as the v1 strategy rather than leaving it unaddressed.

---

## Query Concept Assessment

### Strengths

- The separation of concerns across `highlights`, `locals`, `injections`, and `tags` is well-explained and justified.
- The phased rollout (stubs → raw passthrough → low-level IR → category-specific models → refined authoring story) is sensible.
- The analysis of Path A vs. Path B is balanced and honest about tradeoffs.

### Concerns

- **The query object model may be over-engineered for the actual problem.** Tree-sitter queries are declarative S-expression patterns. They are conceptually simpler than grammar rules. A class-like Nim object model for queries (with `NodePattern`, `FieldPattern`, `Capture`, `Predicate`, etc.) may add more complexity than it removes compared to writing `.scm` files directly. The strongest value proposition is **validation against the grammar model**, not ergonomic authoring improvement.

- **The Path A vs. Path B decision should not be deferred indefinitely.** The concept recommends deferring the choice, but the grammar model's `Grammar` type definition will either include a `queries` field or not. Adding it later is a breaking change. The concept should decide whether `Grammar` will have an optional `queries: Option[QuerySet]` field from the start, even if the query types themselves are not implemented in v1.

### Recommendation

For v1, the grammar model should include an optional, opaque query configuration field that allows raw `.scm` file passthrough. This satisfies the "don't paint yourself into a corner" goal without implementing the full query DSL:

```nim
Grammar(
  name = "mylang",
  rules = @[...],
  queryFiles = some(QueryFiles(
    highlights = some(readFile("queries/highlights.scm")),
    tags = some(readFile("queries/tags.scm")),
  ))
)
```

This is essentially Phase 2 of the query rollout built into the v1 grammar model.

---

## Nim-Specific Implementation Considerations

### Expression Hierarchy Design

This is the single most consequential implementation decision for TreeNimph's API feel. The concept should address it directly.

**Option 1: Object Variants**

```nim
type
  ExprKind = enum
    ekRef, ekText, ekRegex, ekSequence, ekChoice,
    ekOptional, ekZeroOrMore, ekOneOrMore,
    ekField, ekAlias, ekToken, ekPrecedence

  Expr = ref object
    case kind: ExprKind
    of ekRef: refName: string
    of ekText: textValue: string
    of ekRegex: pattern: string
    of ekSequence, ekChoice: items: seq[Expr]
    of ekOptional, ekZeroOrMore, ekOneOrMore, ekToken: item: Expr
    of ekField: fieldName: string; fieldExpr: Expr
    of ekAlias: aliasName: string; aliasExpr: Expr; aliasNamed: bool
    of ekPrecedence: precLevel: int; precAssoc: Assoc; precExpr: Expr
```

Pros: idiomatic Nim, efficient, pattern-matchable with `case`.
Cons: field names must be unique across variants (hence `refName`, `textValue` instead of just `name`, `value`), construction requires the `kind` discriminator.

To get the clean construction syntax from the concept examples, wrapper procs are needed:

```nim
proc Ref(name: string): Expr =
  Expr(kind: ekRef, refName: name)

proc Text(value: string): Expr =
  Expr(kind: ekText, textValue: value)

proc Sequence(items: varargs[Expr]): Expr =
  Expr(kind: ekSequence, items: @items)
```

**Option 2: Ref Inheritance**

```nim
type
  Expr = ref object of RootObj
  RefExpr = ref object of Expr
    name: string
  TextExpr = ref object of Expr
    value: string
  SequenceExpr = ref object of Expr
    items: seq[Expr]
```

Pros: each type has clean field names, construction is natural.
Cons: requires runtime type checks (`of` operator) for dispatch, less idiomatic in modern Nim, no exhaustive pattern matching.

**Recommendation:** Object variants with constructor procs (Option 1) is the stronger choice. It is more idiomatic, enables exhaustive `case` matching in the renderer and validator, and the constructor procs give users the clean API surface shown in the concept examples. The concept should commit to this approach.

### Nimble Package Structure

The concept's suggested repository layout is reasonable but should use Nim conventions:

- The main entry point should be `src/treenimph.nim` which re-exports the public API.
- Internal modules should be under `src/treenimph/` (e.g., `src/treenimph/model.nim`, `src/treenimph/validate.nim`).
- The `.nimble` file should be at the project root.

```text
treenimph/
  treenimph.nimble
  src/
    treenimph.nim                # public API re-exports
    treenimph/
      model.nim
      validate.nim
      render_js.nim
      render_package.nim
      export_pkg.nim             # "export" is a Nim keyword
      helpers.nim
      diagnostics.nim
  tests/
    ...
```

Note: `export` is a reserved word in Nim. The export module should be named something else (e.g., `export_pkg.nim`, `exporter.nim`, or `package_export.nim`).

---

## Testing Strategy Assessment

The testing strategy is sound at a high level. Specific additions to consider:

1. **Round-trip tests:** Define a grammar in TreeNimph, export it, run `tree-sitter generate`, parse sample source code, and verify the parse tree. This is the ultimate correctness check.

2. **Comparison tests:** Hand-write equivalent `grammar.js` files and compare TreeNimph's output against them. This catches rendering drift and ensures the generated JS is semantically equivalent.

3. **Error message snapshot tests:** Validation error messages are a user-facing API surface. Snapshot-test them to prevent regressions in error quality.

4. **Property-based tests:** For the renderer, property-based tests can verify invariants like "all `Ref` names in the rendered JS correspond to rule names defined in the grammar."

---

## Missing Considerations

### 1. Word Grammar and Precedence of Rules

The concept does not mention Tree-sitter's `word` rule — the special rule that identifies the grammar's word token for keyword extraction. This is a required concept for many grammars and should be supported in the `Grammar` type:

```nim
Grammar(
  name = "mylang",
  word = some("identifier"),  # the word rule
  rules = @[...],
)
```

### 2. Extras, Conflicts, Supertypes, and Inline Rules

These are mentioned once in passing under `Grammar`'s responsibilities but are not explored. They are important for non-trivial grammars:

- **`extras`**: tokens that can appear anywhere (whitespace, comments). How are they specified? As `seq[Expr]`?
- **`conflicts`**: explicit conflict declarations for GLR parsing. As `seq[seq[string]]` (sequences of rule name tuples)?
- **`supertypes`**: rules that act as abstract node types. As `seq[string]`?
- **`inline`**: rules that should be inlined and not create named nodes. As `seq[string]`?

These should be specified in the concept because they affect the `Grammar` type's field set and the `grammar.js` renderer.

### 3. Hidden Rules (Underscore Prefix Convention)

Tree-sitter treats rules whose names start with `_` as hidden (they don't create named nodes in the syntax tree). The concept does not address this. Options:

- Preserve the convention: rules named `_expression` are hidden.
- Add an explicit field: `Rule(name = "expression", hidden = true)`.
- Both: allow either approach.

**Recommendation:** Support the explicit `hidden` field and automatically apply it for underscore-prefixed names. This keeps the API explicit while remaining compatible with Tree-sitter conventions.

### 4. Anonymous vs. Named Nodes

In Tree-sitter, string literals like `"="` create anonymous nodes while rule references create named nodes. The concept's `Text` type handles anonymous nodes, but the distinction between named and anonymous `Alias` targets is not discussed. Tree-sitter's `alias` function has a `named` parameter that determines whether the alias creates a named or anonymous node. The `Alias` type should expose this.

### 5. Immediate Tokens

Tree-sitter has `token.immediate(rule)` which creates a token that must appear immediately after the preceding token with no whitespace. The concept mentions `Token` but not `ImmediateToken`. This is used in real grammars (e.g., string escape sequences).

---

## Prioritized Recommendations

### Must Address Before Implementation

1. **Decide the expression hierarchy strategy** — object variants with constructor procs is the recommendation.
2. **Specify `Grammar` type fields completely** — include `word`, `extras`, `conflicts`, `supertypes`, `inline`, and optional query passthrough.
3. **Decide the precedence representation** — Option B (single type with assoc field) is recommended.
4. **Rename the `export` module** — `export` is a Nim keyword.
5. **Add `ImmediateToken` and `Alias.named`** to the expression type set.
6. **Address hidden rule convention** — explicit `hidden` field on `Rule`.

### Should Address Before v1 Release

7. **Evaluate verbosity with a realistic grammar** — write at least one 20-30 rule grammar end-to-end.
8. **Define export idempotency and file ownership semantics.**
9. **Provide variadic constructors** for `Sequence`, `Choice`, and `Grammar.rules` to reduce `@[]` noise.
10. **Specify the v1 error reporting strategy** — grammar-domain locations, not source locations.

### Can Defer to Post-v1

11. Source-location-aware validation.
12. Query DSL beyond raw passthrough.
13. Rule graph visualization and documentation generation.
14. Property-based and round-trip testing infrastructure.

---

## Final Assessment

TreeNimph is a well-conceived library with a clear purpose, disciplined scope, and a genuine value proposition. The composability model and pre-export validation are its strongest differentiators. The concept documents demonstrate thorough understanding of Tree-sitter's ecosystem and a mature perspective on where TreeNimph fits within it.

The primary risk is not conceptual but implementational: the gap between the clean pseudo-Nim shown in the examples and the actual Nim code required to achieve that API surface. Object variants, `ref` semantics, sequence construction syntax, and reserved word conflicts all need explicit resolution. The concept should evolve from "this is the intended style" to "this is the concrete Nim type definition and constructor set that achieves the intended style."

The query concept is well-explored but correctly deferred. The main action item is to ensure the v1 `Grammar` type does not foreclose future query integration by including an optional passthrough field from the start.

Overall: **strong concept, ready for implementation planning once the Nim-specific design decisions identified above are resolved.**
