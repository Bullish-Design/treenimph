# TreeNimph Query Concept

## Status

This document explores **future query support** for TreeNimph.

For **v1**, TreeNimph should remain focused on the **grammar DSL only**.
Query authoring should be treated as a later expansion, but it is worth designing early so the grammar model, export layout, and package structure do not paint the project into a corner.

This document covers:

1. what Tree-sitter queries are
2. what they are used for
3. why the ecosystem separates queries into `highlights`, `locals`, `injections`, and `tags`
4. what a TreeNimph query DSL could look like
5. two design paths:
   - **Path A:** queries defined inside the main grammar file
   - **Path B:** queries defined in separate TreeNimph query files, mirroring Tree-sitter’s standard split
6. recommended direction and staged rollout

---

## 1. What Tree-sitter queries are

A Tree-sitter grammar defines how source text is parsed into a syntax tree.
A **Tree-sitter query** is a separate pattern-matching language for finding structures *inside that tree*.

In other words:

- the **grammar** answers: “What is this source code structurally?”
- **queries** answer: “Which parts of the tree should be highlighted, tagged, treated as locals, or reparsed as embedded code?”

Queries are written as S-expression-like patterns that match node shapes, node fields, and child relationships, and can attach **captures** to matched nodes. Tree-sitter’s official query syntax documentation defines them as one or more patterns that match nodes in the syntax tree, and explains captures, fields, wildcards, anonymous nodes, and predicates.[^query-syntax]

A query can be thought of as a declarative search over the already-built parse tree.

### Example

A normal query pattern might look like this:

```scheme
(function_definition
  name: (identifier) @name) @definition.function
```

This means:

- match a `function_definition` node
- look at its `name` field
- match an `identifier` there
- capture that child as `@name`
- capture the full function node as `@definition.function`

This pattern is useful for **code navigation** rather than parsing.

---

## 2. What queries do

Queries are how Tree-sitter grammars become useful to editors, highlighters, search tools, and code navigation systems.

A parser alone gives you a syntax tree.
Queries tell tools how to interpret that tree for specific features.

### Main uses of queries

#### Syntax highlighting

Queries identify which nodes should be styled as:

- keywords
- strings
- comments
- function names
- types
- properties
- numbers
- operators
- punctuation

Tree-sitter’s syntax-highlighting system is built around query files stored in grammar repositories under `queries/`, and the official highlighting docs describe `highlights.scm` as one of the main language-specific inputs.[^highlighting]

#### Local variable tracking

Queries can identify:

- scopes
- variable definitions
- variable references

This allows editors/highlighters to color a local variable consistently throughout its scope, rather than treating every identifier the same. Tree-sitter documents a `locals` query file with standardized captures like `@local.scope`, `@local.definition`, and `@local.reference`.[^highlighting]

#### Language injections

Queries can identify parts of a syntax tree that should be parsed using another language.

Examples:

- JavaScript inside HTML
- SQL inside string literals
- CSS inside template strings
- Markdown code fences with language labels

Tree-sitter documents this through `injections.scm`, with captures such as `@injection.content` and optionally `@injection.language`.[^highlighting]

#### Code navigation / symbol extraction

Queries can identify definitions and references such as:

- function definitions
- method definitions
- class definitions
- function calls
- variable references

Tree-sitter’s code navigation system uses `tags.scm`, with conventions like `@definition.function`, `@reference.call`, and an inner `@name` capture for the symbol name.[^code-navigation]

---

## 3. Why queries are separated into `highlights`, `locals`, `injections`, and `tags`

Tree-sitter separates queries by **feature domain**.
This is not arbitrary; it reflects how different tools consume the syntax tree.

### `queries/highlights.scm`

Purpose:
- syntax coloring and token styling

Typical captures:
- `@keyword`
- `@string`
- `@comment`
- `@function`
- `@type`
- `@operator`

This file answers:
> “How should the tree be visually styled?”

### `queries/locals.scm`

Purpose:
- local scope tracking

Typical captures:
- `@local.scope`
- `@local.definition`
- `@local.reference`

This file answers:
> “What introduces a scope, what defines a local, and what refers to it?”

### `queries/injections.scm`

Purpose:
- embedded-language parsing

Typical captures:
- `@injection.content`
- `@injection.language`

This file answers:
> “Which subtree or text span should be reparsed as another language?”

### `queries/tags.scm`

Purpose:
- code navigation and symbol indexing

Typical captures:
- `@definition.function`
- `@definition.class`
- `@reference.call`
- `@name`
- optional `@doc`

This file answers:
> “Which nodes are the important named entities and references in this language?”

### Why not keep everything together?

Because the same syntax node can matter differently depending on the feature.

For example, a function definition might be:

- `@function` in highlighting
- `@definition.function` plus `@name` in tags
- a local scope in locals
- irrelevant to injections

Keeping these concerns separate has multiple benefits:

- simpler mental model per file
- easier maintenance
- easier tool consumption
- fewer accidental interactions between unrelated query sets
- alignment with the standard Tree-sitter repository structure[^highlighting][^code-navigation]

For TreeNimph, this standard separation matters because the exported package should look and behave like a normal Tree-sitter language package.

---

## 4. Why queries matter for TreeNimph

TreeNimph’s core promise is:

> Write Tree-sitter language infrastructure in a class-like, composable, Python-friendly Nim style, then export a normal Tree-sitter package.

Queries fit that promise naturally.

Even if TreeNimph v1 only handles grammars, the exported package will eventually need query files if users want:

- editor highlighting
- semantic local-variable highlighting
- embedded language support
- symbol navigation

So TreeNimph should treat queries as a **planned future companion layer** rather than an afterthought.

The important principle is:

> TreeNimph may provide a nicer authoring experience, but the export format must remain standard Tree-sitter.

That means the output should still be:

- `queries/highlights.scm`
- `queries/locals.scm`
- `queries/injections.scm`
- `queries/tags.scm`

No matter how elegant the authoring DSL becomes.

---

## 5. Design goals for a TreeNimph query DSL

If TreeNimph eventually supports queries directly, the query API should follow the same philosophy as the grammar DSL:

- one primary style
- class-like objects rather than symbolic host-language tricks
- composable building blocks
- explicit names and fields
- export to standard Tree-sitter files
- support for reuse and validation

### Key goals

#### 1. Keep the exported result standard

TreeNimph should generate standard `.scm` query files, not invent a new runtime format.

#### 2. Keep the authoring model class-like and composable

Users should be able to define reusable query fragments in the host language.

#### 3. Preserve the feature split

Even if query authoring is integrated into one Nim file, TreeNimph should still export separate `highlights`, `locals`, `injections`, and `tags` files.

#### 4. Allow validation against the grammar

Because TreeNimph controls the grammar model, query validation can be stronger than hand-authored `.scm` files.

Examples of validation opportunities:

- node type does not exist
- field name does not exist on the matched node
- capture kind is invalid for the query category
- references to hidden or anonymous structures are malformed
- impossible injection configuration

#### 5. Support composition and reuse

Users should be able to create reusable fragments such as:

- a query for all identifier-like names
- a query for all declaration forms
- a query fragment shared by both highlighting and tagging

---

## 6. A class-like TreeNimph query model

A future query DSL should probably mirror the grammar approach:

- typed objects
- named fields
- composable fragments
- host-language reuse

### Conceptual object model

```nim
QuerySet(
  highlights = HighlightQueries(...),
  locals = LocalQueries(...),
  injections = InjectionQueries(...),
  tags = TagQueries(...),
)
```

Within each category, users would compose typed query patterns.

### Core building blocks

A future object model might include concepts like:

- `NodePattern`
- `FieldPattern`
- `Wildcard`
- `Capture`
- `Predicate`
- `Match`
- `QueryPattern`
- `QueryGroup`

And category-specific wrappers like:

- `HighlightRule`
- `LocalScopeRule`
- `InjectionRule`
- `TagRule`

### Example conceptual style

```nim
let querySet = QuerySet(
  highlights = HighlightQueries(
    rules = @[
      HighlightRule(
        pattern = NodePattern(
          kind = "function_definition",
          fields = @[
            FieldPattern(
              name = "name",
              pattern = NodePattern(kind = "identifier")
            )
          ]
        ),
        captures = @[
          Capture(path = @[FieldPath("name")], name = "function")
        ]
      )
    ]
  )
)
```

This is intentionally more model-like than raw S-expressions.

Whether this exact shape is ideal is less important than the core design principle:

> Query definitions should feel like structured objects, not embedded strings.

---

## 7. Two main implementation paths

There are two strong design paths for TreeNimph query support.

# Path A — Integrated queries inside the main grammar file

In this path, the user writes **one TreeNimph file** that defines:

- grammar rules
- query definitions
- export configuration

TreeNimph then exports:

- `grammar.js`
- package metadata
- generated parser artifacts
- `queries/highlights.scm`
- `queries/locals.scm`
- `queries/injections.scm`
- `queries/tags.scm`

### Example shape

```nim
let grammar = Grammar(
  name = "mylang",
  rules = @[
    Rule(name = "function_definition", body = ...),
    Rule(name = "identifier", body = ...),
  ],
  queries = QuerySet(
    highlights = HighlightQueries(
      rules = @[
        HighlightRule(
          pattern = NodePattern(kind = "identifier"),
          captures = @[
            Capture.self("variable")
          ]
        )
      ]
    ),
    tags = TagQueries(
      rules = @[
        TagDefinitionRule(
          node = "function_definition",
          nameField = "name",
          nameNode = "identifier",
          kind = "function"
        )
      ]
    )
  )
)
```

## Advantages of Path A

### 1. Single source of truth

The grammar and its queries live together.
That makes it easier to keep them synchronized.

### 2. Better validation

Because query definitions live inside the same model as the grammar, TreeNimph can validate them directly against the grammar’s node names and known fields.

### 3. Better composability

Users can define reusable building blocks once and reuse them across grammar rules and query definitions.

For example:

```nim
let
  IdentifierRef = Ref("identifier")
  IdentifierNode = NodePattern(kind = "identifier")
```

Even if these are different object types, they can be derived from the same conceptual source.

### 4. Better discoverability

A user opening the grammar file sees the full language definition story in one place.

### 5. Easier package generation

The export step can automatically produce all required files from one object graph.

## Drawbacks of Path A

### 1. Large files

For mature languages, grammar and queries together can become very large.

### 2. Mixed concerns

Grammar development and query tuning are related but not identical tasks.
A single file may become harder to navigate.

### 3. Harder collaboration boundaries

Some contributors may want to work only on highlighting or tags without editing the grammar definition.

### 4. More complex file organization later

If the project grows, users may eventually want internal modularity anyway.

## Best version of Path A

The best integrated design is not “one giant blob.”
It is:

- one top-level TreeNimph file
- but with internal sections or imported modules
- exported into standard Tree-sitter layout

For example:

```nim
import mylang/grammar_rules
import mylang/highlight_queries
import mylang/tag_queries

let grammar = Grammar(
  name = "mylang",
  rules = grammarRules,
  queries = QuerySet(
    highlights = highlightQueries,
    tags = tagQueries,
    locals = localQueries,
    injections = injectionQueries,
  )
)
```

This still counts as the integrated path because the **authoring model** is one TreeNimph language-definition object, even if Nim modules help organize it.

---

# Path B — Separate query DSL files mirroring Tree-sitter’s split

In this path, TreeNimph still provides a class-like query DSL, but users author each query category in its own file or module.

Examples:

- `grammar.nim`
- `highlights.nim`
- `locals.nim`
- `injections.nim`
- `tags.nim`

TreeNimph then exports each one to the standard `.scm` path.

### Example shape

```nim
# grammar.nim
let grammar = Grammar(
  name = "mylang",
  rules = @[
    Rule(name = "function_definition", body = ...),
    Rule(name = "identifier", body = ...),
  ]
)
```

```nim
# highlights.nim
let highlights = HighlightQueries(
  rules = @[
    HighlightRule(
      pattern = NodePattern(kind = "identifier"),
      captures = @[
        Capture.self("variable")
      ]
    )
  ]
)
```

```nim
# tags.nim
let tags = TagQueries(
  rules = @[
    TagDefinitionRule(
      node = "function_definition",
      nameField = "name",
      nameNode = "identifier",
      kind = "function"
    )
  ]
)
```

And then:

```nim
let package = TreeNimphPackage(
  grammar = grammar,
  highlights = highlights,
  tags = tags,
  locals = locals,
  injections = injections,
)
```

## Advantages of Path B

### 1. Mirrors Tree-sitter’s mental model

Users can think in the same categories the ecosystem already uses.

### 2. Cleaner separation of concerns

Highlighting logic, symbol tagging, and injection behavior are edited independently.

### 3. Easier scaling

For larger languages, separate files are often much easier to maintain.

### 4. Easier contributor workflow

People can specialize in grammar, highlighting, or code navigation.

### 5. Clear export mapping

Each TreeNimph query module maps directly to one output file.

## Drawbacks of Path B

### 1. More files to manage

This is the obvious cost.

### 2. Slightly weaker cohesion

The grammar and queries are no longer defined in one place.

### 3. Validation requires cross-file linking

Still very possible, but the system must explicitly load all pieces together.

### 4. Slightly more setup for small projects

Tiny grammars may feel over-structured at first.

---

## 8. Shared implementation requirements across both paths

No matter which path TreeNimph chooses, several design principles should stay fixed.

### A. Export standard `.scm` files

The end result must always be the standard query files that existing tools expect.

### B. Preserve category-specific capture semantics

Not every capture name is appropriate everywhere.

Examples:

- `@keyword` is highlight-oriented
- `@local.scope` is local-analysis-oriented
- `@injection.content` is injection-specific
- `@definition.function` is tags-oriented

A TreeNimph DSL should encode or validate those expectations where possible.

### C. Validate against the grammar model

This is one of TreeNimph’s strongest opportunities.

Because TreeNimph knows the grammar structure, it can validate query definitions better than plain `.scm` files can.

Potential checks include:

- unknown node type
- impossible field constraint
- capture category mismatch
- unsupported injection target setup
- malformed tag definition lacking `@name`

### D. Support reusable fragments

Query authoring should be composable just like grammar authoring.

For example:

```nim
let NameIdentifier = NodePattern(kind = "identifier")

let FunctionNamePattern = NodePattern(
  kind = "function_definition",
  fields = @[
    FieldPattern(name = "name", pattern = NameIdentifier)
  ]
)
```

Then reused for:

- highlighting the function name
- tagging the function definition
- marking the symbol in locals if relevant

### E. Keep the authoring style class-like

No alternate symbolic syntax.
No separate “compatibility mode.”

The user should always be working with structured objects and composable values.

---

## 9. A practical future object model for queries

A likely future design is to create a shared low-level query IR plus category-specific convenience layers.

### Low-level IR

A generic query AST might include:

- `Pattern`
- `NodePattern`
- `FieldPattern`
- `Capture`
- `Predicate`
- `QueryDocument`

This is what all category-specific query types eventually lower into.

### Category-specific wrappers

On top of that low-level IR, TreeNimph could offer category-specific models that are more ergonomic and more strongly validated.

Examples:

- `HighlightRule`
- `TagDefinitionRule`
- `TagReferenceRule`
- `LocalScopeRule`
- `LocalDefinitionRule`
- `LocalReferenceRule`
- `InjectionContentRule`

This layered model would let TreeNimph remain internally regular while keeping the user-facing API expressive.

---

## 10. Interaction between the grammar DSL and the query DSL

Even if query authoring is separate, the grammar model and query model should be closely linked.

### Important opportunities

#### Shared node names

The query layer should validate node references using the grammar’s exported node types or internal rule metadata.

#### Shared field names

If a rule exposes fields such as `name`, `body`, or `value`, the query layer should validate those references.

#### Shared reusable concepts

Users may want to define language concepts once and use them both in grammar and queries.

Examples:

- identifiers
- declarations
- comments
- string content
- expression-like nodes

TreeNimph should not collapse grammar and query objects into the same type, but it should make it easy to keep them aligned.

---

## 11. Recommendation

### Recommended long-term design

The better long-term design is:

- **v1:** grammar DSL only
- **v2+:** query DSL added as a second structured layer
- support both integrated and separate authoring internally
- but choose one primary external authoring story

### Which path is stronger?

If forced to choose a single eventual default, **Path B** is the stronger long-term maintenance story:

- it mirrors Tree-sitter’s own conceptual split
- it scales better for real grammars
- it is easier to maintain in larger projects
- it keeps feature-specific concerns clearer

However, **Path A** is extremely attractive for user experience, especially for smaller grammars and for a “single-file language definition” workflow.

### Best compromise

The best overall design may be:

- one TreeNimph package object at export time
- but separate authoring modules/files by default
- with a fully supported option to define everything in one file if desired

That preserves the standard Tree-sitter output while letting users choose an organizational style.

If TreeNimph must eventually enforce only one authoring style, then the real decision is philosophical:

- choose **Path A** if “single-source language definition” is the top priority
- choose **Path B** if “long-term maintainability and ecosystem mirroring” is the top priority

For TreeNimph as currently envisioned, **Path A feels more aligned with the project identity**, while **Path B feels more aligned with mature grammar maintenance**.

---

## 12. Suggested rollout plan

### Phase 1

Grammar only.

Export query stub files as empty placeholders:

- `queries/highlights.scm`
- `queries/locals.scm`
- `queries/injections.scm`
- `queries/tags.scm`

### Phase 2

Allow raw query strings or file passthroughs inside the TreeNimph package export model.

This gives users full power immediately, while TreeNimph still exports a standard package.

### Phase 3

Add a low-level class-based query IR.

### Phase 4

Add category-specific convenience models and validation.

### Phase 5

Refine integrated vs separate authoring story based on real usage.

---

## 13. Final takeaway

Tree-sitter queries are not part of parsing itself.
They are the layer that makes a parsed tree useful for highlighting, locals analysis, code navigation, and embedded-language handling.

For TreeNimph, this means:

- queries should remain a future layer, not part of v1 scope
- when added, they should follow the same class-like, composable, Python-friendly design principles as the grammar DSL
- no matter how elegant the authoring model becomes, TreeNimph must export standard Tree-sitter query files

The two strongest designs are:

- **Integrated path:** grammar and queries authored together in one TreeNimph language-definition file
- **Separated path:** grammar and query categories authored in distinct TreeNimph DSL files that mirror Tree-sitter’s file layout

Both can work.
The right choice depends on whether TreeNimph wants to optimize more for:

- single-file cohesion
- or long-term modular maintainability

The one thing that should not change is the export boundary:

> TreeNimph can innovate on authoring, but the generated output must remain standard Tree-sitter.

---

## References

[^query-syntax]: Tree-sitter documentation, “Query Syntax.” https://tree-sitter.github.io/tree-sitter/using-parsers/queries/1-syntax.html
[^highlighting]: Tree-sitter documentation, “Syntax Highlighting.” https://tree-sitter.github.io/tree-sitter/3-syntax-highlighting.html
[^code-navigation]: Tree-sitter documentation, “Code Navigation Systems.” https://tree-sitter.github.io/tree-sitter/4-code-navigation.html
