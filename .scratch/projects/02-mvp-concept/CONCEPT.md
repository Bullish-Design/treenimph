# TreeNimph MVP Concept

## What TreeNimph Is

TreeNimph is a Nim library for authoring Tree-sitter grammars as composable typed objects and exporting them as standard Tree-sitter grammar packages.

Users define grammars by constructing a graph of typed Nim objects — `Grammar`, `Rule`, `Sequence`, `Choice`, `Ref`, `Text`, `Field`, and others — then export the result as a conventional Tree-sitter package containing a generated `grammar.js` and the expected directory layout. TreeNimph validates the grammar model before export and can optionally invoke `tree-sitter generate` to produce final parser artifacts.

TreeNimph is **not** a parser generator. It does **not** replace Tree-sitter. It is a frontend authoring layer that makes grammar writing more ergonomic, composable, validated, and maintainable while preserving full compatibility with the existing Tree-sitter toolchain.

The compatibility boundary is the generated `grammar.js` and standard package structure. Downstream consumers never need to know TreeNimph exists.

---

## Core Design Goals

1. **Single authoring style** — one coherent, class-like design centered on typed objects. No split between a "friendly API" and a "compatibility API."

2. **Composable by default** — reusable building blocks through ordinary Nim variables, fragments, and helper procs.

3. **Low visual noise** — convenience constructors (variadic, short-form) are part of the core API, not afterthoughts. Verbosity is acceptable; unnecessary visual noise is not.

4. **Strict Tree-sitter compatibility** — the generated output is a standard Tree-sitter package. The official `tree-sitter generate` remains the parser-generation source of truth.

5. **Strong pre-export validation** — structured object graphs enable early, domain-aware error detection before `tree-sitter generate` ever runs.

6. **Clear boundaries** — TreeNimph innovates on authoring. The generated output is conventional. Debugging remains possible by reading emitted JS.

---

## Non-Goals

- Reimplement the Tree-sitter parser generator
- Replace `tree-sitter generate`
- Introduce a custom parser backend
- Require downstream tools to understand Nim
- Create multiple first-class authoring syntaxes
- Build a Nim-native scanner DSL (v1 supports scanner file passthrough only)
- Build a query DSL (v1 supports raw query file passthrough only)

---

## Expression Hierarchy Design

This is the most consequential implementation decision for TreeNimph's API feel. The expression hierarchy defines how users construct grammar rules, how the library validates them, and how the renderer traverses them.

This section investigates three viable approaches, evaluates each, and makes a recommendation.

### The Requirements

The expression hierarchy must support:

1. **~15 expression variants** — `Ref`, `Text`, `Regex`, `Sequence`, `Choice`, `Optional`, `ZeroOrMore`, `OneOrMore`, `Field`, `Alias`, `Token`, `ImmediateToken`, `Precedence`, and `Blank`
2. **Recursive nesting** — a `Field` contains an `Expr`, a `Sequence` contains `seq[Expr]`, etc.
3. **Clean construction syntax** — users should write `Ref("identifier")`, not `Expr(kind: ekRef, refName: "identifier")`
4. **Exhaustive traversal** — the renderer and validator must handle every expression type, and the compiler should catch missing cases
5. **Composability** — expressions are stored in Nim variables, passed to procs, and assembled into larger structures
6. **Varargs support** — `Sequence(a, b, c)` instead of `Sequence(items = @[a, b, c])`

### Option A: Ref Object Variants with Constructor Procs

Define a single `Expr` type as a `ref object` with a `case kind` discriminator. Expose constructor procs that hide the variant construction details.

#### Type Definition

```nim
type
  ExprKind* = enum
    ekRef, ekText, ekRegex, ekBlank,
    ekSequence, ekChoice,
    ekOptional, ekZeroOrMore, ekOneOrMore,
    ekField, ekAlias,
    ekToken, ekImmediateToken,
    ekPrecedence

  Assoc* = enum
    assocNone, assocLeft, assocRight, assocDynamic

  Expr* = ref object
    case kind*: ExprKind
    of ekRef: refName*: string
    of ekText: textValue*: string
    of ekRegex: regexPattern*: string
    of ekBlank: discard
    of ekSequence, ekChoice: items*: seq[Expr]
    of ekOptional, ekZeroOrMore, ekOneOrMore: item*: Expr
    of ekToken, ekImmediateToken: tokenExpr*: Expr
    of ekField: fieldName*: string; fieldExpr*: Expr
    of ekAlias: aliasName*: string; aliasExpr*: Expr; aliasNamed*: bool
    of ekPrecedence: precLevel*: int; precAssoc*: Assoc; precExpr*: Expr
```

#### Constructor Procs

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

#### User Experience

```nim
let
  id = Ref("identifier")
  expr = Ref("expression")

let assignment = Rule("assignment", Sequence(
  Field("target", id),
  Text("="),
  Field("value", expr),
))

let statement = Rule("statement", Choice(
  Ref("assignment"),
  Ref("expression"),
))

let grammar = Grammar(
  name = "mylang",
  rules = [assignment, statement],
)
```

#### Internal Traversal

```nim
proc renderExpr(e: Expr): string =
  case e.kind
  of ekRef: result = "$." & e.refName
  of ekText: result = "'" & e.textValue & "'"
  of ekRegex: result = "/" & e.regexPattern & "/"
  of ekBlank: result = "blank()"
  of ekSequence: result = "seq(" & e.items.mapIt(renderExpr(it)).join(", ") & ")"
  of ekChoice: result = "choice(" & e.items.mapIt(renderExpr(it)).join(", ") & ")"
  of ekOptional: result = "optional(" & renderExpr(e.item) & ")"
  of ekZeroOrMore: result = "repeat(" & renderExpr(e.item) & ")"
  of ekOneOrMore: result = "repeat1(" & renderExpr(e.item) & ")"
  of ekField: result = "field('" & e.fieldName & "', " & renderExpr(e.fieldExpr) & ")"
  of ekAlias: result = "alias(" & renderExpr(e.aliasExpr) & ", $.." & e.aliasName & ")"
  of ekToken: result = "token(" & renderExpr(e.tokenExpr) & ")"
  of ekImmediateToken: result = "token.immediate(" & renderExpr(e.tokenExpr) & ")"
  of ekPrecedence:
    let fn = case e.precAssoc
      of assocNone: "prec"
      of assocLeft: "prec.left"
      of assocRight: "prec.right"
      of assocDynamic: "prec.dynamic"
    result = fn & "(" & $e.precLevel & ", " & renderExpr(e.precExpr) & ")"
```

#### Pros

- **Exhaustive `case` matching** — the compiler catches missing expression types in the renderer and validator. This is a significant safety property for a code generator.
- **Single type** — all expressions are `Expr`. No type casting needed when composing. Varargs, sequences, and assignment all work naturally.
- **Recursive via `ref`** — `ref object` allows self-referential fields without infinite size.
- **Constructor procs hide internal field names** — users never see `refName`, `textValue`, `fieldExpr` etc. They see `Ref("identifier")`, `Text("=")`, `Field("target", expr)`.
- **Idiomatic Nim** — this is the canonical AST pattern in Nim. Nim's own compiler uses it.
- **Efficient** — single allocation per node, discriminator is an enum (integer), no RTTI overhead.
- **Shared fields possible** — if metadata (e.g., source location) is needed later, shared fields can be placed before the `case` block.

#### Cons

- **Internal field names are ugly** — `refName`, `textValue`, `fieldExpr` etc. are needed because Nim does not allow the same field name in different variant branches. This affects internal library code (renderer, validator) but not user-facing code.
- **Cannot add new variants from outside the module** — the enum is closed. This is actually a feature for TreeNimph (the expression set is fixed), but it means third-party extensions must be done differently.
- **Discriminator is visible** — `e.kind` is accessible to users. Not harmful, but exposes an implementation detail.

#### Implications

- The internal library code reads `e.refName` instead of `e.name` in the renderer. This is cosmetic friction that only library authors see.
- The user-facing API is clean and lightweight. Users never interact with `ExprKind` or variant field names directly.
- The compiler enforces completeness in every `case e.kind` block, preventing silent bugs when new expression types are added.

---

### Option B: Ref Object Inheritance with Method Dispatch

Define `Expr` as a base `ref object of RootObj` and each expression type as a subtype.

#### Type Definition

```nim
type
  Expr* = ref object of RootObj

  RefExpr* = ref object of Expr
    name*: string

  TextExpr* = ref object of Expr
    value*: string

  RegexExpr* = ref object of Expr
    pattern*: string

  BlankExpr* = ref object of Expr

  SequenceExpr* = ref object of Expr
    items*: seq[Expr]

  ChoiceExpr* = ref object of Expr
    items*: seq[Expr]

  OptionalExpr* = ref object of Expr
    item*: Expr

  ZeroOrMoreExpr* = ref object of Expr
    item*: Expr

  OneOrMoreExpr* = ref object of Expr
    item*: Expr

  FieldExpr* = ref object of Expr
    name*: string
    expr*: Expr

  AliasExpr* = ref object of Expr
    name*: string
    expr*: Expr
    named*: bool

  TokenExpr* = ref object of Expr
    expr*: Expr

  ImmediateTokenExpr* = ref object of Expr
    expr*: Expr

  PrecedenceExpr* = ref object of Expr
    level*: int
    assoc*: Assoc
    expr*: Expr
```

#### Constructor Procs

```nim
proc Ref*(name: string): Expr =
  RefExpr(name: name)

proc Text*(value: string): Expr =
  TextExpr(value: value)

proc Sequence*(items: varargs[Expr]): Expr =
  SequenceExpr(items: @items)

proc Field*(name: string, expr: Expr): Expr =
  FieldExpr(name: name, expr: expr)

# ... etc
```

#### User Experience

```nim
# Identical to Option A from the user's perspective
let assignment = Rule("assignment", Sequence(
  Field("target", Ref("identifier")),
  Text("="),
  Field("value", Ref("expression")),
))
```

The user-facing API looks the same because the constructor procs return `Expr`.

#### Internal Traversal

```nim
method renderExpr(e: Expr): string {.base.} =
  raise newException(ValueError, "unknown expression type")

method renderExpr(e: RefExpr): string =
  "$." & e.name

method renderExpr(e: TextExpr): string =
  "'" & e.value & "'"

method renderExpr(e: SequenceExpr): string =
  "seq(" & e.items.mapIt(renderExpr(it)).join(", ") & ")"

method renderExpr(e: FieldExpr): string =
  "field('" & e.name & "', " & renderExpr(e.expr) & ")"

# ... one method per type
```

Or, using manual `of` checks instead of methods:

```nim
proc renderExpr(e: Expr): string =
  if e of RefExpr:
    result = "$." & RefExpr(e).name
  elif e of TextExpr:
    result = "'" & TextExpr(e).value & "'"
  elif e of SequenceExpr:
    result = "seq(" & SequenceExpr(e).items.mapIt(renderExpr(it)).join(", ") & ")"
  # ... etc
  else:
    raise newException(ValueError, "unknown expression type")
```

#### Pros

- **Clean field names** — each type has natural names: `name`, `value`, `items`, `expr`. No prefixing needed. Internal library code reads naturally.
- **Natural OOP feel** — familiar to developers coming from Python, Java, or similar. Each expression type is a real, named type.
- **Open for extension** — new expression types can be added in other modules. (Not needed for TreeNimph, but it is a structural property.)
- **Method dispatch available** — `method` provides dynamic dispatch without explicit `case` statements.

#### Cons

- **No exhaustive matching** — this is the critical weakness. The compiler cannot verify that every expression type is handled. If a new type is added, there is no compile-time error for missing handlers. The `else` branch in an `if/elif` chain or the base `method` becomes a runtime error rather than a compile-time one.
- **Many types to define** — 15+ separate type definitions instead of one `case` object. More boilerplate in the type definition layer.
- **Casting required for field access** — after matching `e of FieldExpr`, you must cast with `FieldExpr(e).name`. This is verbose and error-prone.
- **Method dispatch overhead** — methods use vtable-like dispatch. Minor performance cost, but more importantly, method definitions are scattered across the codebase, making it harder to see all cases in one place.
- **Methods and closures interact poorly in Nim** — there are known edge cases with method resolution when generics or closures are involved.

#### Implications

- The lack of exhaustive matching is a serious concern for a code generator. When a new expression type is added (e.g., `ImmediateToken` was not in the original concept), every renderer, validator, and introspection proc must be updated. With inheritance, the compiler will not catch omissions — they become runtime errors discovered during testing or, worse, in user code.
- The clean field names are genuinely nice for internal code, but this benefit is concentrated in the library internals, not in the user-facing API (which uses constructor procs in all options).

---

### Option C: Ref Object Variants with Accessor Procs

A hybrid that uses object variants internally but provides accessor procs that normalize field access, combining the compiler safety of Option A with cleaner internal code.

#### Type Definition

Same as Option A.

#### Accessor Procs

```nim
# Uniform accessors for common patterns
proc name*(e: Expr): string =
  case e.kind
  of ekRef: e.refName
  of ekField: e.fieldName
  of ekAlias: e.aliasName
  else: raise newException(FieldDefect, "expression kind " & $e.kind & " has no 'name' field")

proc value*(e: Expr): string =
  case e.kind
  of ekText: e.textValue
  else: raise newException(FieldDefect, "expression kind " & $e.kind & " has no 'value' field")

proc inner*(e: Expr): Expr =
  ## The single child expression for wrappers (Optional, ZeroOrMore, etc.)
  case e.kind
  of ekOptional, ekZeroOrMore, ekOneOrMore: e.item
  of ekToken, ekImmediateToken: e.tokenExpr
  of ekField: e.fieldExpr
  of ekAlias: e.aliasExpr
  of ekPrecedence: e.precExpr
  else: raise newException(FieldDefect, "expression kind " & $e.kind & " has no inner expression")
```

#### Internal Traversal

Renderer still uses exhaustive `case` matching (same as Option A), but utility code can use the accessor procs for convenience:

```nim
proc collectRefs(e: Expr): seq[string] =
  case e.kind
  of ekRef: @[e.refName]
  of ekSequence, ekChoice:
    result = @[]
    for child in e.items:
      result.add(collectRefs(child))
  of ekOptional, ekZeroOrMore, ekOneOrMore, ekToken, ekImmediateToken,
     ekField, ekAlias, ekPrecedence:
    collectRefs(e.inner)  # accessor simplifies grouped access
  of ekText, ekRegex, ekBlank:
    @[]
```

#### Pros

- All the pros of Option A (exhaustive matching, single type, idiomatic Nim).
- Accessor procs make internal code more readable where exhaustive matching is not needed.
- The accessor layer is purely internal convenience — it does not change the user-facing API.

#### Cons

- Accessor procs that raise on invalid kinds are partial functions — they can fail at runtime. But they are only used internally, and the exhaustive `case` in the renderer/validator is the primary safety mechanism.
- Slightly more code to write and maintain than pure Option A.

---

### Recommendation: Option A with Accessor Procs (Option C)

**Use ref object variants as the core type, with constructor procs for the user-facing API and accessor procs for internal convenience.**

Reasoning:

1. **Exhaustive matching is non-negotiable for a code generator.** TreeNimph's renderer must produce correct `grammar.js` for every expression type. A missing case must be a compile-time error, not a runtime crash. Option B (inheritance) cannot provide this guarantee. This alone is decisive.

2. **The user-facing API is identical across all options.** Users write `Ref("identifier")`, `Sequence(a, b, c)`, `Field("target", expr)` regardless of the internal representation. The constructor procs fully abstract the variant construction.

3. **Internal field name ugliness is contained.** The `refName`, `textValue`, `fieldExpr` naming is only visible inside the library's own renderer, validator, and utility code. Accessor procs can smooth this over where grouping is natural. Users never see it.

4. **This is idiomatic Nim.** The Nim compiler itself, the Nim standard library's `macros` module, and most Nim AST-processing libraries use this exact pattern. Library contributors will recognize it immediately.

5. **Performance is optimal.** Single allocation, integer discriminator, no vtable dispatch. Not that performance is critical for a grammar authoring tool, but there is no reason to pay costs for features (open extensibility, dynamic dispatch) that TreeNimph does not need.

---

## Grammar Model

### `Rule`

Represents a named grammar rule.

```nim
type
  Rule* = object
    name*: string
    body*: Expr
    hidden*: bool
```

Constructor:

```nim
proc Rule*(name: string, body: Expr, hidden = false): Rule =
  Rule(name: name, body: body, hidden: hidden)
```

Rules whose names start with `_` are automatically marked `hidden = true` for compatibility with Tree-sitter's underscore convention. Users can also set `hidden` explicitly.

### `Grammar`

Represents the complete grammar package definition.

```nim
type
  Grammar* = object
    name*: string
    rules*: seq[Rule]
    word*: Option[string]         # the word rule for keyword extraction
    extras*: seq[Expr]            # tokens that can appear anywhere (whitespace, comments)
    conflicts*: seq[seq[string]]  # explicit GLR conflict declarations
    supertypes*: seq[string]      # rules that act as abstract node types
    inline*: seq[string]          # rules inlined during parsing (no named nodes)
    externals*: seq[Expr]         # external scanner token declarations
    queryFiles*: Option[QueryFiles]  # raw query file passthrough
    scannerPath*: Option[string]  # path to existing scanner.c for passthrough
```

Constructor:

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

### `QueryFiles`

Raw query file passthrough for v1. Users provide `.scm` content as strings.

```nim
type
  QueryFiles* = object
    highlights*: Option[string]
    locals*: Option[string]
    injections*: Option[string]
    tags*: Option[string]
```

This allows users to include hand-written query files in their TreeNimph package without waiting for a full query DSL.

---

## Precedence Representation

Precedence uses a single type with an `assoc` field (Option B from the initial concept review):

```nim
# Part of the Expr variant:
of ekPrecedence: precLevel*: int; precAssoc*: Assoc; precExpr*: Expr

# Assoc enum:
type Assoc* = enum
  assocNone,    # prec(n, rule)
  assocLeft,    # prec.left(n, rule)
  assocRight,   # prec.right(n, rule)
  assocDynamic  # prec.dynamic(n, rule)
```

Convenience constructors:

```nim
proc Prec*(level: int, expr: Expr, assoc = assocNone): Expr
proc PrecLeft*(level: int, expr: Expr): Expr
proc PrecRight*(level: int, expr: Expr): Expr
proc PrecDynamic*(level: int, expr: Expr): Expr
```

This maps directly to Tree-sitter's four precedence forms while keeping the type hierarchy minimal.

---

## Hidden Rules

Tree-sitter treats rules whose names start with `_` as hidden — they do not create named nodes in the syntax tree.

TreeNimph supports this through both convention and explicit configuration:

```nim
# Convention: underscore prefix automatically sets hidden = true
let expr = Rule("_expression", Choice(
  Ref("identifier"),
  Ref("number"),
))
# expr.hidden == true (automatic)

# Explicit: set hidden directly
let expr2 = Rule("expression", Choice(
  Ref("identifier"),
  Ref("number"),
), hidden = true)
# rendered as _expression in grammar.js
```

When `hidden = true` and the name does not start with `_`, the renderer prepends `_` in the generated `grammar.js`. When a name starts with `_`, the `Rule` constructor automatically sets `hidden = true`.

---

## Alias Named Flag

Tree-sitter's `alias` function has a `named` parameter that determines whether the alias creates a named node (appears in the AST with a type name) or an anonymous node (like a string literal).

```nim
# Named alias (default): creates a named node type
Alias("block_expression", Ref("expression"))
# renders as: alias($.expression, $.block_expression)

# Anonymous alias: creates an anonymous node
Alias("=>", Text("->"), named = false)
# renders as: alias('->', '=>')
```

---

## ImmediateToken

Tree-sitter's `token.immediate(rule)` creates a token that must appear immediately after the preceding token with no intervening extras (whitespace/comments). Used in real grammars for string escape sequences, template literals, etc.

```nim
# String content that must follow the opening quote immediately
ImmediateToken(Regex("[^\"\\\\]+"))
# renders as: token.immediate(/[^"\\]+/)
```

---

## Complete Expression Type Set (v1)

| Constructor | Description | Tree-sitter JS Equivalent |
|---|---|---|
| `Ref(name)` | Reference to another rule | `$.name` |
| `Text(value)` | Literal string match | `'value'` |
| `Regex(pattern)` | Regular expression match | `/pattern/` |
| `Blank()` | Empty/epsilon match | `blank()` |
| `Sequence(items...)` | Ordered sequence | `seq(a, b, c)` |
| `Choice(items...)` | Ordered alternatives | `choice(a, b, c)` |
| `Optional(item)` | Zero or one | `optional(x)` |
| `ZeroOrMore(item)` | Zero or more (repeat) | `repeat(x)` |
| `OneOrMore(item)` | One or more (repeat1) | `repeat1(x)` |
| `Field(name, expr)` | Named field | `field('name', x)` |
| `Alias(name, expr, named?)` | Node type alias | `alias(x, $.name)` |
| `Token(expr)` | Combine into single token | `token(x)` |
| `ImmediateToken(expr)` | Immediate token (no extras) | `token.immediate(x)` |
| `Prec(level, expr, assoc?)` | Precedence with optional associativity | `prec(n, x)` |
| `PrecLeft(level, expr)` | Left-associative precedence | `prec.left(n, x)` |
| `PrecRight(level, expr)` | Right-associative precedence | `prec.right(n, x)` |
| `PrecDynamic(level, expr)` | Dynamic precedence | `prec.dynamic(n, x)` |

---

## Example Grammar

A realistic example showing the intended authoring style for a simple expression language.

```nim
import treenimph

# Reusable fragments
let
  id = Ref("identifier")
  expr = Ref("_expression")
  comma = Text(",")

# Helper for comma-separated lists
proc commaList(item: Expr, trailing = false): Expr =
  if trailing:
    Sequence(item, ZeroOrMore(Sequence(comma, item)), Optional(comma))
  else:
    Sequence(item, ZeroOrMore(Sequence(comma, item)))

# Grammar definition
let grammar = Grammar(
  name = "example",
  word = some("identifier"),
  extras = @[Regex("\\s+"), Ref("comment")],
  rules = [
    Rule("source_file", ZeroOrMore(Ref("_statement"))),

    Rule("_statement", Choice(
      Ref("assignment"),
      Ref("expression_statement"),
    )),

    Rule("assignment", Sequence(
      Field("target", id),
      Text("="),
      Field("value", expr),
      Text(";"),
    )),

    Rule("expression_statement", Sequence(
      Field("expression", expr),
      Text(";"),
    )),

    Rule("_expression", Choice(
      Ref("identifier"),
      Ref("number"),
      Ref("string"),
      Ref("binary_expression"),
      Ref("call_expression"),
      Ref("parenthesized_expression"),
    )),

    Rule("binary_expression", PrecLeft(1, Sequence(
      Field("left", expr),
      Field("operator", Choice(Text("+"), Text("-"))),
      Field("right", expr),
    ))),

    Rule("call_expression", Prec(2, Sequence(
      Field("function", expr),
      Text("("),
      Optional(Field("arguments", commaList(expr, trailing = true))),
      Text(")"),
    ))),

    Rule("parenthesized_expression", Sequence(
      Text("("),
      Field("expression", expr),
      Text(")"),
    )),

    Rule("identifier", Regex("[a-zA-Z_][a-zA-Z0-9_]*")),
    Rule("number", Regex("[0-9]+")),

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
      Regex("[\"\\\\nrt]"),
    ))),

    Rule("comment", Token(Sequence(
      Text("//"),
      Regex("[^\\n]*"),
    ))),
  ],
)

# Validate and export
grammar.validateOrRaise()
grammar.export(ExportConfig(
  outDir = "dist/tree-sitter-example",
  runGenerate = true,
  writeQueryStubs = true,
))
```

---

## Composability Model

Three levels of composition, all using ordinary Nim.

### Level 1: Reusable Expression Values

```nim
let
  id = Ref("identifier")
  comma = Text(",")
  semicolon = Text(";")
```

### Level 2: Reusable Composite Fragments

```nim
let parameterList = Sequence(
  Text("("),
  Optional(commaList(Ref("parameter"))),
  Text(")"),
)
```

### Level 3: Reusable Helper Constructors

```nim
proc delimitedList(item: Expr, sep: Expr, trailing = false): Expr =
  if trailing:
    Sequence(item, ZeroOrMore(Sequence(sep, item)), Optional(sep))
  else:
    Sequence(item, ZeroOrMore(Sequence(sep, item)))

proc balanced(open, close: string, content: Expr): Expr =
  Sequence(Text(open), content, Text(close))

proc keyword(word: string): Expr =
  Text(word)
```

The helper layer is part of the core library for common patterns, but users are equally empowered to write their own.

---

## Validation Model

### Core Validation Checks (v1)

- **Duplicate rule names** — two rules with the same name
- **Undefined `Ref` targets** — a `Ref("foo")` where no rule named `"foo"` exists
- **Empty `Choice`** — `Choice()` with zero items
- **Empty `Sequence`** — `Sequence()` with zero items
- **Invalid field names** — field names that are not valid Tree-sitter identifiers
- **Invalid alias names** — alias names that are not valid identifiers
- **Invalid `word` reference** — `word` names a rule that does not exist
- **Invalid `extras` references** — extras contain `Ref` to nonexistent rules
- **Invalid `conflicts` references** — conflict arrays reference nonexistent rules
- **Invalid `supertypes` references** — supertype names that are not defined rules
- **Invalid `inline` references** — inline names that are not defined rules
- **Invalid `externals` references** — external `Ref` targets that conflict with rule names unexpectedly
- **Missing scanner file** — `scannerPath` is set but the file does not exist

### Error Reporting Strategy (v1)

Errors reference grammar-domain locations — rule names and expression paths within rules — rather than Nim source locations. This is pragmatic and sufficient for v1.

```
Error: Unknown rule reference "identifer" in rule "assignment"
  Hint: Did you mean "identifier"?

Error: Duplicate rule name "expression"
  First defined as rule #3, redefined as rule #7

Error: Choice must contain at least one item
  In rule "statement", within Field("value", ...)

Error: Word rule "ident" does not exist
  Hint: Did you mean "identifier"?
```

Errors are structured objects, not just strings:

```nim
type
  DiagnosticKind* = enum
    dkError, dkWarning

  Diagnostic* = object
    kind*: DiagnosticKind
    message*: string
    ruleName*: Option[string]
    hint*: Option[string]
```

### Future Validation Enhancements (post-v1)

- Suspicious self-references
- Unreachable rules
- Likely typos with "did you mean" suggestions
- Repeated literal patterns that should be centralized
- Source-location-aware errors via `instantiationInfo()` macros

---

## Rendering

### `grammar.js` Generation

The renderer converts the grammar model into a canonical, deterministic `grammar.js` file.

Design principles for rendered output:

- **Deterministic** — same model always produces identical output
- **Readable** — conventionally formatted, easy to inspect
- **Diffable** — minimal unnecessary changes between versions
- **Conventional** — looks like hand-written Tree-sitter `grammar.js`
- **Marked as generated** — header comment identifies TreeNimph as the source

Example rendered output:

```js
// Generated by TreeNimph — do not edit manually.

module.exports = grammar({
  name: 'example',

  word: $ => $.identifier,

  extras: $ => [
    /\s+/,
    $.comment,
  ],

  rules: {
    source_file: $ => repeat($._statement),

    _statement: $ => choice(
      $.assignment,
      $.expression_statement,
    ),

    assignment: $ => seq(
      field('target', $.identifier),
      '=',
      field('value', $._expression),
      ';',
    ),

    // ... etc
  }
});
```

---

## Export

### Export Configuration

```nim
type
  ExportConfig* = object
    outDir*: string
    runGenerate*: bool           # invoke tree-sitter generate after export
    scannerPath*: Option[string] # override Grammar.scannerPath
    writeQueryStubs*: bool       # create empty query files if none provided
    overwrite*: bool             # overwrite existing generated files
```

### Export Flow

1. Validate the grammar model — fail early with structured errors
2. Create the output directory structure
3. Write `grammar.js` (always generated, marked with header comment)
4. Write `package.json`
5. Write `tree-sitter.json`
6. Write query files (from `queryFiles` passthrough, or stubs if `writeQueryStubs`)
7. Copy `scanner.c` if configured
8. Optionally run `tree-sitter generate`
9. Verify expected outputs exist

### File Ownership Policy

- Files generated by TreeNimph include a `// Generated by TreeNimph` header comment
- TreeNimph only writes files it owns — it never overwrites files it does not recognize
- The export operation is idempotent: same grammar model produces identical output bytes
- User-authored files in the export directory (without the TreeNimph header) are preserved

### Export Directory Structure

```text
<outDir>/
  grammar.js              # generated by TreeNimph
  package.json            # generated by TreeNimph
  tree-sitter.json        # generated by TreeNimph
  queries/
    highlights.scm        # from queryFiles passthrough or stub
    locals.scm            # from queryFiles passthrough or stub
    injections.scm        # from queryFiles passthrough or stub
    tags.scm              # from queryFiles passthrough or stub
  src/
    scanner.c             # copied from scannerPath if configured
    parser.c              # produced by tree-sitter generate
    node-types.json       # produced by tree-sitter generate
```

---

## Introspection and Debugging

```nim
# Render grammar.js as a string without writing to disk
let js = grammar.renderGrammarJs()

# Run validation independently of export
let diagnostics = grammar.validate()
for d in diagnostics:
  echo d

# Print a summary of defined rules and references
echo grammar.summary()
# Output:
#   Grammar: example (15 rules)
#   Word: identifier
#   Extras: /\s+/, comment
#   Rules: source_file, _statement, assignment, ...
```

---

## Internal Architecture

### Module Layout

```text
treenimph/
  treenimph.nimble
  src/
    treenimph.nim                # public API re-exports
    treenimph/
      model.nim                  # Expr, Rule, Grammar type definitions + constructors
      validate.nim               # validation traversal and diagnostic generation
      render_js.nim              # grammar.js renderer
      render_package.nim         # package.json, tree-sitter.json renderers
      exporter.nim               # file writing, directory creation, toolchain invocation
      helpers.nim                # delimitedList, balanced, keyword, etc.
      diagnostics.nim            # Diagnostic type, formatting, "did you mean" logic
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
```

Note: the export module is named `exporter.nim` because `export` is a Nim keyword.

### Layer Responsibilities

1. **Model** (`model.nim`) — type definitions, constructor procs, accessor procs. No side effects.

2. **Validation** (`validate.nim`) — traverses the model, produces `seq[Diagnostic]`. No side effects.

3. **JS Renderer** (`render_js.nim`) — converts model to `grammar.js` string. No side effects.

4. **Package Renderer** (`render_package.nim`) — generates `package.json`, `tree-sitter.json`, query stubs. No side effects.

5. **Exporter** (`exporter.nim`) — writes files to disk, copies scanner, invokes `tree-sitter generate`. This is the only layer with side effects.

6. **Helpers** (`helpers.nim`) — reusable constructor procs for common grammar patterns. Returns `Expr` values. No side effects.

7. **Diagnostics** (`diagnostics.nim`) — diagnostic types, formatting, string distance for "did you mean" suggestions. No side effects.

---

## Development Plan

### Phase 1: Core Model

- Define `ExprKind`, `Expr`, `Assoc`, `Rule`, `Grammar` types
- Implement all constructor procs with varargs support
- Implement accessor procs for internal convenience
- Write unit tests for construction and composition

### Phase 2: Validation

- Implement all core validation checks
- Implement diagnostic formatting
- Implement "did you mean" suggestions using string distance
- Write unit tests for each validation rule

### Phase 3: `grammar.js` Rendering

- Implement the `renderExpr` case dispatch
- Implement `renderGrammarJs` for the full grammar
- Ensure deterministic, readable, diffable output
- Write snapshot tests against known Tree-sitter grammars

### Phase 4: Package Export

- Implement `package.json` and `tree-sitter.json` generation
- Implement query file writing (passthrough and stubs)
- Implement scanner file passthrough
- Implement directory creation and file ownership policy
- Write integration tests

### Phase 5: Toolchain Integration

- Implement optional `tree-sitter generate` invocation
- Implement output verification after generation
- Provide actionable errors when the external tool fails

### Phase 6: Polish

- Implement `grammar.summary()` introspection
- Add helper constructors (`delimitedList`, `balanced`, etc.)
- Write example grammars
- Refine error messages and diagnostics

---

## Testing Strategy

### Unit Tests

- Model construction: every expression type, every constructor signature
- Composition: fragments stored in variables, passed to procs, assembled into rules
- Validation: one test per validation rule, including edge cases
- Renderer: expression-level rendering for each type

### Snapshot Tests

- Full `grammar.js` output for complete example grammars
- `package.json` and `tree-sitter.json` output
- Validation error message formatting

### Comparison Tests

- Hand-write equivalent `grammar.js` files and verify TreeNimph's output matches semantically

### Integration Tests

- Export a sample grammar, run `tree-sitter generate`, verify the parse tree for sample input
- Verify file ownership policy (generated files have headers, user files are preserved)

### Error Message Snapshot Tests

- Snapshot-test diagnostic output to prevent regressions in error quality

---

## Risks and Mitigations

### Visual Noise at Scale

**Risk:** For large grammars (50-200 rules), even with convenience constructors, the Nim code may feel noisier than equivalent JS.

**Mitigation:** Composability is the primary tool. Reusable fragments, helper procs, and the variadic constructors significantly reduce per-rule noise. The library should ship with enough helpers that common patterns are concise.

### Tree-sitter DSL Coverage Gaps

**Risk:** Tree-sitter's grammar DSL has nuances that the model fails to represent.

**Mitigation:** Design the expression model around actual Tree-sitter concepts (done — the type set maps 1:1 to Tree-sitter's functions). Snapshot-test rendered output against known grammars. The `grammar.js` compatibility boundary means any gap is visible in the generated output.

### Over-Abstraction

**Risk:** The model feels too distant from Tree-sitter for experienced users.

**Mitigation:** Preserve Tree-sitter semantics closely. The expression type names (`Sequence`, `Choice`, `Field`, `Ref`) map directly to Tree-sitter DSL functions (`seq`, `choice`, `field`, `$`). The rendered output is readable and comparable to hand-written grammars.

### Nim Ecosystem Size

**Risk:** Small Nim ecosystem means fewer users and contributors.

**Mitigation:** TreeNimph's output is standard Tree-sitter — it does not lock anyone into Nim. Users who outgrow TreeNimph can take the generated `grammar.js` and maintain it directly.
