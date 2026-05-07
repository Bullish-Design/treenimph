# TreeNimph MVP Specification

This document specifies every type, constructor, validation rule, rendering rule, and export behavior for TreeNimph v1. It is intended to be precise enough to drive implementation and testing directly.

---

## 1. Type Definitions

### 1.1 `ExprKind`

```nim
type ExprKind* = enum
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
```

Closed enum. 14 variants. All traversal code (`case e.kind`) must be exhaustive.

### 1.2 `Assoc`

```nim
type Assoc* = enum
  assocNone     # prec(n, rule)
  assocLeft     # prec.left(n, rule)
  assocRight    # prec.right(n, rule)
  assocDynamic  # prec.dynamic(n, rule)
```

### 1.3 `Expr`

```nim
type Expr* = ref object
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

`Expr` is a `ref object` to support recursive nesting. All expressions are the same type; there is no inheritance hierarchy. Users never construct `Expr` directly — they use constructor procs.

### 1.4 `Rule`

```nim
type Rule* = object
  name*: string
  body*: Expr
  hidden*: bool
```

Value type. `hidden` controls whether the rule produces named nodes in the parse tree.

### 1.5 `Grammar`

```nim
type Grammar* = object
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
```

### 1.6 `QueryFiles`

```nim
type QueryFiles* = object
  highlights*: Option[string]
  locals*: Option[string]
  injections*: Option[string]
  tags*: Option[string]
```

Each field holds raw `.scm` file content as a string.

### 1.7 `ExportConfig`

```nim
type ExportConfig* = object
  outDir*: string
  runGenerate*: bool
  writeQueryStubs*: bool
  overwrite*: bool
```

- `outDir`: required, the target directory for the exported package.
- `runGenerate`: if true, invoke `tree-sitter generate` after writing files. Default: `false`.
- `writeQueryStubs`: if true, write empty query files when `Grammar.queryFiles` does not provide them. Default: `true`.
- `overwrite`: if true, overwrite existing TreeNimph-generated files. If false, raise an error if a generated file already exists. Default: `true`.

### 1.8 `DiagnosticKind`

```nim
type DiagnosticKind* = enum
  dkError
  dkWarning
```

### 1.9 `Diagnostic`

```nim
type Diagnostic* = object
  kind*: DiagnosticKind
  message*: string
  ruleName*: Option[string]
  hint*: Option[string]
```

---

## 2. Constructor Procs

All constructor procs are public (`*`). All return the appropriate type. Users interact exclusively through these procs — they should never need to write `Expr(kind: ...)` directly.

### 2.1 Expression Constructors

#### `Ref`

```nim
proc Ref*(name: string): Expr
```

Creates a reference to another rule.

- `name` must be non-empty.
- `name` may start with `_` (hidden rule reference).

#### `Text`

```nim
proc Text*(value: string): Expr
```

Creates a literal string match.

- `value` must be non-empty.

#### `Regex`

```nim
proc Regex*(pattern: string): Expr
```

Creates a regular expression match.

- `pattern` must be non-empty.
- `pattern` is stored verbatim. TreeNimph does not validate regex syntax — Tree-sitter's generator handles that.

#### `Blank`

```nim
proc Blank*(): Expr
```

Creates an empty/epsilon match. No arguments.

#### `Sequence`

```nim
proc Sequence*(items: varargs[Expr]): Expr
```

Creates an ordered sequence of expressions.

- Accepts zero or more arguments via varargs.
- Validation will reject a `Sequence` with zero items.

#### `Choice`

```nim
proc Choice*(items: varargs[Expr]): Expr
```

Creates an ordered set of alternatives.

- Accepts zero or more arguments via varargs.
- Validation will reject a `Choice` with zero items.

#### `Optional`

```nim
proc Optional*(item: Expr): Expr
```

Matches zero or one occurrence.

- `item` must not be nil.

#### `ZeroOrMore`

```nim
proc ZeroOrMore*(item: Expr): Expr
```

Matches zero or more occurrences (repeat).

- `item` must not be nil.

#### `OneOrMore`

```nim
proc OneOrMore*(item: Expr): Expr
```

Matches one or more occurrences (repeat1).

- `item` must not be nil.

#### `Field`

```nim
proc Field*(name: string, expr: Expr): Expr
```

Assigns a field name to a child expression.

- `name` must be non-empty.
- `name` must be a valid identifier: matches `^[a-zA-Z_][a-zA-Z0-9_]*$`.
- `expr` must not be nil.

#### `Alias`

```nim
proc Alias*(name: string, expr: Expr, named = true): Expr
```

Gives a node an alternative name in the syntax tree.

- `name` must be non-empty.
- `expr` must not be nil.
- When `named = true`: the alias creates a named node type. Rendered as `alias(expr, $.name)`.
- When `named = false`: the alias creates an anonymous node. Rendered as `alias(expr, 'name')`.

#### `Token`

```nim
proc Token*(expr: Expr): Expr
```

Combines a complex rule into a single token.

- `expr` must not be nil.

#### `ImmediateToken`

```nim
proc ImmediateToken*(expr: Expr): Expr
```

Like `Token`, but the resulting token must appear immediately after the preceding token (no intervening extras).

- `expr` must not be nil.

#### `Prec`

```nim
proc Prec*(level: int, expr: Expr, assoc = assocNone): Expr
```

Assigns precedence (and optionally associativity) to a rule.

- `expr` must not be nil.
- `level` may be any integer (negative values are valid in Tree-sitter).

#### `PrecLeft`

```nim
proc PrecLeft*(level: int, expr: Expr): Expr
```

Shorthand for `Prec(level, expr, assocLeft)`.

#### `PrecRight`

```nim
proc PrecRight*(level: int, expr: Expr): Expr
```

Shorthand for `Prec(level, expr, assocRight)`.

#### `PrecDynamic`

```nim
proc PrecDynamic*(level: int, expr: Expr): Expr
```

Shorthand for `Prec(level, expr, assocDynamic)`.

### 2.2 Rule Constructor

```nim
proc Rule*(name: string, body: Expr, hidden = false): Rule
```

- `name` must be non-empty.
- `body` must not be nil.
- If `name` starts with `_`, `hidden` is forced to `true` regardless of the passed value.
- If `hidden = true` and `name` does not start with `_`, the renderer prepends `_` to the name in the generated `grammar.js`.

### 2.3 Grammar Constructor

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
): Grammar
```

- `name` must be non-empty.
- `name` must match `^[a-zA-Z_][a-zA-Z0-9_]*$`.
- `rules` must contain at least one rule.
- The first rule in `rules` is the start rule of the grammar (this is a Tree-sitter requirement).

---

## 3. Accessor Procs

Internal convenience accessors for the library implementation. These are public but intended primarily for internal use and advanced users. They raise `FieldDefect` on invalid access.

### 3.1 `inner`

```nim
proc inner*(e: Expr): Expr
```

Returns the single child expression for wrapper types.

- Valid for: `ekOptional`, `ekZeroOrMore`, `ekOneOrMore`, `ekToken`, `ekImmediateToken`, `ekField`, `ekAlias`, `ekPrecedence`.
- Raises `FieldDefect` for all other kinds.

Mapping:
| Kind | Field returned |
|---|---|
| `ekOptional`, `ekZeroOrMore`, `ekOneOrMore` | `e.item` |
| `ekToken`, `ekImmediateToken` | `e.tokenExpr` |
| `ekField` | `e.fieldExpr` |
| `ekAlias` | `e.aliasExpr` |
| `ekPrecedence` | `e.precExpr` |

### 3.2 `children`

```nim
proc children*(e: Expr): seq[Expr]
```

Returns all direct child expressions.

| Kind | Result |
|---|---|
| `ekRef`, `ekText`, `ekRegex`, `ekBlank` | `@[]` (empty) |
| `ekSequence`, `ekChoice` | `e.items` |
| `ekOptional`, `ekZeroOrMore`, `ekOneOrMore` | `@[e.item]` |
| `ekToken`, `ekImmediateToken` | `@[e.tokenExpr]` |
| `ekField` | `@[e.fieldExpr]` |
| `ekAlias` | `@[e.aliasExpr]` |
| `ekPrecedence` | `@[e.precExpr]` |

---

## 4. Validation

Validation is performed by `proc validate*(g: Grammar): seq[Diagnostic]`. It returns all errors and warnings found. It does not raise — callers inspect the result.

A convenience proc `proc validateOrRaise*(g: Grammar)` calls `validate`, collects all diagnostics with `kind == dkError`, and raises a `ValidationError` with a formatted multi-line message if any errors exist.

```nim
type ValidationError* = object of CatchableError
```

### 4.1 Validation Context

Before running checks, the validator builds a **rule name set**: the set of all `rule.name` values (using the canonical name — with `_` prefix applied if `hidden = true`). This set is used for reference resolution throughout validation.

The canonical name for a rule is:
- If `rule.hidden == true` and `rule.name` does not start with `_`: `"_" & rule.name`
- Otherwise: `rule.name`

### 4.2 Validation Rules

Each rule below specifies: the condition that triggers it, the diagnostic kind, the message format, and whether a hint is generated.

---

#### V01: Grammar name must be non-empty

- **Condition:** `grammar.name.len == 0`
- **Kind:** `dkError`
- **Message:** `Grammar name must not be empty`
- **Hint:** none
- **Rule name:** none

#### V02: Grammar name must be a valid identifier

- **Condition:** `grammar.name` does not match `^[a-zA-Z_][a-zA-Z0-9_]*$`
- **Kind:** `dkError`
- **Message:** `Grammar name "<name>" is not a valid identifier`
- **Hint:** none
- **Rule name:** none

#### V03: Grammar must have at least one rule

- **Condition:** `grammar.rules.len == 0`
- **Kind:** `dkError`
- **Message:** `Grammar must define at least one rule`
- **Hint:** none
- **Rule name:** none

#### V04: Duplicate rule names

- **Condition:** Two or more rules have the same canonical name.
- **Kind:** `dkError`
- **Message:** `Duplicate rule name "<name>"`
- **Hint:** `First defined as rule #<n>, redefined as rule #<m>` (1-indexed)
- **Rule name:** the duplicate name

#### V05: Rule name must be non-empty

- **Condition:** `rule.name.len == 0`
- **Kind:** `dkError`
- **Message:** `Rule name must not be empty`
- **Hint:** `Rule #<n>` (1-indexed position)
- **Rule name:** none

#### V06: Rule name must be a valid identifier

- **Condition:** canonical rule name does not match `^_?[a-zA-Z_][a-zA-Z0-9_]*$`
- **Kind:** `dkError`
- **Message:** `Rule name "<name>" is not a valid identifier`
- **Hint:** none
- **Rule name:** the invalid name

#### V07: Rule name must not start with MISSING or UNEXPECTED

- **Condition:** canonical rule name starts with `MISSING` or `UNEXPECTED` (case-sensitive)
- **Kind:** `dkError`
- **Message:** `Rule name "<name>" uses a reserved prefix`
- **Hint:** `Tree-sitter reserves names starting with "MISSING" and "UNEXPECTED"`
- **Rule name:** the invalid name

#### V08: Rule body must not be nil

- **Condition:** `rule.body == nil`
- **Kind:** `dkError`
- **Message:** `Rule "<name>" has a nil body`
- **Hint:** none
- **Rule name:** the rule name

#### V09: Undefined Ref target

- **Condition:** A `Ref` expression references a name that is not in the rule name set AND not in the externals set.
- **Kind:** `dkError`
- **Message:** `Unknown rule reference "<target>" in rule "<rule>"`
- **Hint:** If a rule name exists within edit distance 2 (Levenshtein): `Did you mean "<suggestion>"?`
- **Rule name:** the containing rule name

The validator walks every expression tree in every rule body and every expression in `grammar.extras` and `grammar.externals` to find all `Ref` nodes. The set of valid names includes:
- All canonical rule names
- All `Ref` names in `grammar.externals`

#### V10: Empty Sequence

- **Condition:** A `Sequence` expression has `items.len == 0`
- **Kind:** `dkError`
- **Message:** `Sequence must contain at least one item`
- **Hint:** `In rule "<rule>"` (if within a rule)
- **Rule name:** the containing rule name (if applicable)

#### V11: Empty Choice

- **Condition:** A `Choice` expression has `items.len == 0`
- **Kind:** `dkError`
- **Message:** `Choice must contain at least one item`
- **Hint:** `In rule "<rule>"` (if within a rule)
- **Rule name:** the containing rule name (if applicable)

#### V12: Invalid field name

- **Condition:** A `Field` expression has a `fieldName` that does not match `^[a-zA-Z_][a-zA-Z0-9_]*$`
- **Kind:** `dkError`
- **Message:** `Invalid field name "<name>" in rule "<rule>"`
- **Hint:** none
- **Rule name:** the containing rule name

#### V13: Invalid alias name (named)

- **Condition:** An `Alias` expression with `aliasNamed == true` has an `aliasName` that does not match `^_?[a-zA-Z_][a-zA-Z0-9_]*$`
- **Kind:** `dkError`
- **Message:** `Invalid alias name "<name>" in rule "<rule>"`
- **Hint:** `Named aliases must be valid identifiers`
- **Rule name:** the containing rule name

#### V14: Empty alias name

- **Condition:** An `Alias` expression has `aliasName.len == 0`
- **Kind:** `dkError`
- **Message:** `Alias name must not be empty in rule "<rule>"`
- **Hint:** none
- **Rule name:** the containing rule name

#### V15: Nil child expression

- **Condition:** Any expression that takes a child expression (`Optional`, `ZeroOrMore`, `OneOrMore`, `Token`, `ImmediateToken`, `Field`, `Alias`, `Prec`) has a nil child.
- **Kind:** `dkError`
- **Message:** `<ExprType> has a nil child expression in rule "<rule>"`
- **Hint:** none
- **Rule name:** the containing rule name

The `<ExprType>` is the user-facing name: `Optional`, `ZeroOrMore`, `OneOrMore`, `Token`, `ImmediateToken`, `Field`, `Alias`, or `Prec`.

#### V16: Nil items in Sequence/Choice

- **Condition:** A `Sequence` or `Choice` contains a nil element in its `items` seq.
- **Kind:** `dkError`
- **Message:** `<Sequence|Choice> contains a nil item at position <n> in rule "<rule>"`
- **Hint:** none
- **Rule name:** the containing rule name

#### V17: Word rule does not exist

- **Condition:** `grammar.word.isSome` and the word value is not in the rule name set.
- **Kind:** `dkError`
- **Message:** `Word rule "<name>" does not exist`
- **Hint:** If a rule name exists within edit distance 2: `Did you mean "<suggestion>"?`
- **Rule name:** none

#### V18: Invalid extras reference

- **Condition:** An `Expr` in `grammar.extras` is a `Ref` whose name is not in the rule name set.
- **Kind:** `dkError`
- **Message:** `Extras reference "<name>" does not match any rule`
- **Hint:** If a rule name exists within edit distance 2: `Did you mean "<suggestion>"?`
- **Rule name:** none

#### V19: Invalid conflicts reference

- **Condition:** A name in any `seq[string]` in `grammar.conflicts` is not in the rule name set.
- **Kind:** `dkError`
- **Message:** `Conflict reference "<name>" does not match any rule`
- **Hint:** If a rule name exists within edit distance 2: `Did you mean "<suggestion>"?`
- **Rule name:** none

#### V20: Invalid supertypes reference

- **Condition:** A name in `grammar.supertypes` is not in the rule name set.
- **Kind:** `dkError`
- **Message:** `Supertype "<name>" does not match any rule`
- **Hint:** If a rule name exists within edit distance 2: `Did you mean "<suggestion>"?`
- **Rule name:** none

#### V21: Invalid inline reference

- **Condition:** A name in `grammar.inline` is not in the rule name set.
- **Kind:** `dkError`
- **Message:** `Inline rule "<name>" does not match any rule`
- **Hint:** If a rule name exists within edit distance 2: `Did you mean "<suggestion>"?`
- **Rule name:** none

#### V22: Empty conflicts entry

- **Condition:** A `seq[string]` in `grammar.conflicts` has fewer than 2 elements.
- **Kind:** `dkError`
- **Message:** `Conflict entry must contain at least 2 rule names`
- **Hint:** none
- **Rule name:** none

#### V23: Scanner file does not exist

- **Condition:** `grammar.scannerPath.isSome` and the file does not exist on disk.
- **Kind:** `dkError`
- **Message:** `Scanner file "<path>" does not exist`
- **Hint:** none
- **Rule name:** none

### 4.3 "Did You Mean" Logic

When a reference (Ref target, word, extras, conflicts, supertypes, inline) does not match any rule name, the validator computes the Levenshtein distance between the invalid name and all rule names. If any rule name has distance ≤ 2, the closest match is offered as a suggestion.

If multiple names tie at the same distance, the one that appears first in the `rules` seq is chosen.

### 4.4 Validation Traversal Order

The validator processes in this order:

1. Grammar-level checks: V01, V02, V03
2. Rule-level checks: for each rule in order — V04, V05, V06, V07, V08
3. Expression tree checks: for each rule body, depth-first pre-order — V09, V10, V11, V12, V13, V14, V15, V16
4. Grammar config checks: V17, V18, V19, V20, V21, V22, V23

All diagnostics are collected. The validator does not short-circuit on the first error.

### 4.5 Diagnostic Formatting

`proc $*(d: Diagnostic): string` renders a diagnostic as a human-readable string.

Format:

```
<Error|Warning>: <message>
```

If `ruleName` is set:

```
<Error|Warning>: <message>
  In rule "<ruleName>"
```

If `hint` is set:

```
<Error|Warning>: <message>
  Hint: <hint>
```

If both are set:

```
<Error|Warning>: <message>
  In rule "<ruleName>"
  Hint: <hint>
```

---

## 5. Rendering

### 5.1 `grammar.js` Structure

The rendered `grammar.js` must have this exact structure:

```javascript
// Generated by TreeNimph — do not edit manually.

module.exports = grammar({
  name: '<name>',

  <word section if present>

  <extras section if non-default>

  <supertypes section if non-empty>

  <inline section if non-empty>

  <conflicts section if non-empty>

  <externals section if non-empty>

  rules: {
    <rule entries>
  }
});
```

Top-level sections are separated by blank lines. Sections that are empty or at default values are omitted entirely.

### 5.2 Header Comment

Every generated `grammar.js` starts with:

```javascript
// Generated by TreeNimph — do not edit manually.
```

Followed by one blank line before `module.exports`.

### 5.3 Indentation

- 2-space indentation throughout.
- No tabs.
- Trailing commas on all array/object items (Tree-sitter convention).

### 5.4 Section Rendering Rules

#### `name`

```javascript
  name: '<name>',
```

The name is rendered as a single-quoted JavaScript string.

#### `word`

Rendered only if `grammar.word.isSome`.

```javascript
  word: $ => $.identifier,
```

The word value references a rule, so it is rendered as `$.<name>` (with `_` prefix if the referenced rule is hidden).

#### `extras`

Rendered only if `grammar.extras` is non-empty. If `grammar.extras` is empty (the seq has zero elements), the section is omitted entirely and Tree-sitter's default (`[/\s/]`) applies.

```javascript
  extras: $ => [
    <rendered exprs>,
  ],
```

Each expression in the extras array is rendered using the standard expression rendering rules (§5.5).

#### `supertypes`

Rendered only if `grammar.supertypes` is non-empty.

```javascript
  supertypes: $ => [
    $.<name>,
    $.<name>,
  ],
```

Each supertype name is rendered as `$.<canonicalName>`.

#### `inline`

Rendered only if `grammar.inline` is non-empty.

```javascript
  inline: $ => [
    $.<name>,
  ],
```

Each inline name is rendered as `$.<canonicalName>`.

#### `conflicts`

Rendered only if `grammar.conflicts` is non-empty.

```javascript
  conflicts: $ => [
    [$.<name>, $.<name>],
    [$.<name>, $.<name>, $.<name>],
  ],
```

Each inner array is rendered on a single line. Each name is rendered as `$.<canonicalName>`.

#### `externals`

Rendered only if `grammar.externals` is non-empty.

```javascript
  externals: $ => [
    <rendered exprs>,
  ],
```

Each expression is rendered using the standard expression rendering rules. Typically these are `Ref` expressions (rendered as `$.<name>`) or `Text` expressions (rendered as string literals).

#### `rules`

```javascript
  rules: {
    <rule_name>: $ => <rendered body>,

    <rule_name>: $ => <rendered body>,
  }
```

Rules are separated by blank lines. Each rule is rendered as `<canonicalName>: $ => <body>`. The canonical name includes the `_` prefix for hidden rules.

If a rule body is simple (renders to a single short expression), it goes on one line:

```javascript
    true: $ => 'true',
```

If a rule body is complex (multi-line), the body starts on the same line as the `=>`:

```javascript
    assignment: $ => seq(
      field('target', $.identifier),
      '=',
      field('value', $._expression),
      ';',
    ),
```

### 5.5 Expression Rendering Rules

Each `ExprKind` maps to a specific JavaScript rendering. The renderer is a recursive function that takes an `Expr` and the current indentation level.

#### `ekRef`

Rendered as a dollar-prefixed rule reference:

```javascript
$.identifier
$._expression
```

The ref name is used verbatim (it already includes the `_` prefix if the user wrote `Ref("_expression")`). However, if the target rule was defined with `hidden = true` and a name without `_`, refs to that rule name must also resolve — validation ensures the name is valid, and the renderer uses the canonical name. **Important:** the renderer does NOT modify ref names. Ref names are rendered exactly as stored. It is the Rule constructor's responsibility to store canonical names, and validation's responsibility to resolve refs against canonical names.

#### `ekText`

Rendered as a single-quoted JavaScript string literal:

```javascript
'='
'function'
'++'
'\n'
'\''
'\\'
```

Escaping rules:
- `\` → `\\`
- `'` → `\'`
- newline → `\n`
- carriage return → `\r`
- tab → `\t`
- All other characters rendered verbatim.

#### `ekRegex`

Rendered as a JavaScript regex literal:

```javascript
/[a-zA-Z_]\w*/
/\s+/
/[^\\"\n]+/
```

The pattern is placed between `/` delimiters. The pattern is rendered verbatim — TreeNimph does not validate or transform regex syntax. Any `/` characters within the pattern must be escaped as `\/`.

Escaping rules for the pattern:
- Unescaped `/` → `\/`

#### `ekBlank`

```javascript
blank()
```

#### `ekSequence`

Rendered as `seq(...)`:

```javascript
seq(
  field('target', $.identifier),
  '=',
  field('value', $._expression),
)
```

If all items render to short single-line expressions and the total line length would be ≤ 80 characters, render on one line:

```javascript
seq($.identifier, '=', $.expression)
```

Otherwise, render multi-line with each item on its own line, indented one level deeper than the `seq(`.

#### `ekChoice`

Rendered as `choice(...)`. Same formatting rules as `ekSequence`:

```javascript
choice(
  $.assignment,
  $.expression_statement,
)
```

Or single-line if short enough:

```javascript
choice($.true, $.false, $.null)
```

#### `ekOptional`

```javascript
optional($.exponent_part)
```

or multi-line if the child is complex:

```javascript
optional(
  seq($.comma, $.expression),
)
```

#### `ekZeroOrMore`

```javascript
repeat($._statement)
```

#### `ekOneOrMore`

```javascript
repeat1($.string_content)
```

#### `ekField`

```javascript
field('target', $.identifier)
```

If the child expression is complex:

```javascript
field('operator', choice(
  '+',
  '-',
  '*',
  '/',
))
```

The field name is rendered as a single-quoted string.

#### `ekAlias`

When `aliasNamed == true`:

```javascript
alias($.expression, $.block_expression)
```

The alias name is rendered as `$.<name>` (a rule reference).

When `aliasNamed == false`:

```javascript
alias('->', '=>')
```

The alias name is rendered as a single-quoted string literal.

#### `ekToken`

```javascript
token(seq(
  '//',
  /.*/,
))
```

or single-line:

```javascript
token(/[a-zA-Z_]\w*/)
```

#### `ekImmediateToken`

```javascript
token.immediate(prec(1, /[^\\"\n]+/))
```

or multi-line:

```javascript
token.immediate(seq(
  '\\',
  /[\\nrt"]/,
))
```

#### `ekPrecedence`

Rendered based on `precAssoc`:

| `precAssoc` | JS function |
|---|---|
| `assocNone` | `prec` |
| `assocLeft` | `prec.left` |
| `assocRight` | `prec.right` |
| `assocDynamic` | `prec.dynamic` |

Format:

```javascript
prec.left(1, seq(
  field('left', $._expression),
  field('operator', choice('+', '-')),
  field('right', $._expression),
))
```

The level is rendered as an integer literal. The child expression follows standard rendering rules.

### 5.6 Line Length and Formatting Heuristic

The renderer uses this heuristic for single-line vs. multi-line rendering:

1. Render each child expression to a string.
2. If all children are single-line AND the total formatted length (including the function name, parens, commas, and spaces) is ≤ 80 characters, render on one line.
3. Otherwise, render multi-line with each child on its own indented line.

"Single-line" means the rendered child string contains no newlines.

### 5.7 Determinism

The renderer must produce byte-identical output for the same `Grammar` object. No randomness, no timestamp, no hostname. The order of rules, extras, conflicts, etc. is preserved exactly as given in the `Grammar` object.

---

## 6. Package Metadata Rendering

### 6.1 `package.json`

Generated content:

```json
{
  "name": "tree-sitter-<grammar_name>",
  "version": "0.1.0",
  "description": "<grammar_name> grammar for tree-sitter",
  "main": "bindings/node",
  "types": "bindings/node",
  "keywords": [
    "incremental",
    "parsing",
    "tree-sitter",
    "<grammar_name>"
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
```

The JSON is rendered with 2-space indentation and a trailing newline.

The header line for `package.json` is **not** included (JSON does not support comments). The file is identified as TreeNimph-generated by its deterministic content.

### 6.2 `tree-sitter.json`

Generated content:

```json
{
  "grammars": [
    {
      "name": "<grammar_name>",
      "scope": "source.<grammar_name>",
      "path": ".",
      "file-types": [],
      "highlights": "queries/highlights.scm",
      "tags": "queries/tags.scm",
      "locals": "queries/locals.scm",
      "injections": "queries/injections.scm"
    }
  ],
  "metadata": {
    "version": "0.1.0",
    "description": "<grammar_name> grammar for tree-sitter",
    "links": {}
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
```

The JSON is rendered with 2-space indentation and a trailing newline.

Query file paths in the `grammars` entry only reference query files that will actually be written (either from `queryFiles` passthrough or stubs if `writeQueryStubs` is true). If a particular query type is not provided and stubs are disabled, its key is omitted from the grammar entry.

---

## 7. Query File Rendering

### 7.1 Passthrough

If `grammar.queryFiles` is set and a specific field (e.g., `highlights`) has content, that content is written verbatim to the corresponding file (e.g., `queries/highlights.scm`).

A header comment is prepended:

```scheme
; Generated by TreeNimph — do not edit manually.

<user content>
```

Wait — this creates a problem: the content is user-provided, not generated. The header should distinguish between passthrough and generated content.

**Revised:** Passthrough query files are written verbatim with **no** header comment. They are user-authored content being placed into the export directory. TreeNimph does not claim ownership of passthrough query files.

### 7.2 Stubs

If `writeQueryStubs` is true and `queryFiles` does not provide content for a given query type, an empty stub file is written:

```scheme
; Generated by TreeNimph — do not edit manually.
```

This single-line comment is the entire file content. Stubs are written for all four query types: `highlights.scm`, `locals.scm`, `injections.scm`, `tags.scm`.

---

## 8. Export

### 8.1 Export Flow

`proc export*(g: Grammar, config: ExportConfig)` performs the full export. It raises on any error.

Steps in order:

1. **Validate.** Call `g.validate()`. If any diagnostics have `kind == dkError`, raise `ValidationError` with formatted messages. Do not proceed.

2. **Create directory structure.**
   - `<outDir>/` (create if not exists)
   - `<outDir>/queries/` (create if not exists)
   - `<outDir>/src/` (create if not exists)

3. **Write `grammar.js`.** Render via `renderGrammarJs()` and write to `<outDir>/grammar.js`. If the file exists and `overwrite` is false, raise an error. If the file exists and `overwrite` is true, overwrite only if the file starts with the TreeNimph header comment. If the file exists without the header, raise an error (refuse to overwrite user-authored files).

4. **Write `package.json`.** Render and write to `<outDir>/package.json`. Same overwrite rules as `grammar.js`, except `package.json` cannot have a comment header (it's JSON). For `package.json`, the overwrite check uses content comparison: if the file exists and its parsed JSON has `"name"` matching `"tree-sitter-<grammar_name>"`, it is considered TreeNimph-generated and can be overwritten. If it exists and the name does not match, raise an error.

5. **Write `tree-sitter.json`.** Same overwrite rules as `package.json` (check `grammars[0].name` match).

6. **Write query files.** For each of the four query types:
   - If `queryFiles` provides content: write verbatim (no header). Overwrite policy: always overwrite (passthrough content is authoritative).
   - Else if `writeQueryStubs`: write stub (with header). Overwrite policy: only overwrite if file starts with the TreeNimph header comment or does not exist.
   - Else: skip.

7. **Copy scanner.** If `grammar.scannerPath.isSome`:
   - Read the source file.
   - Write to `<outDir>/src/scanner.c`.
   - Overwrite policy: always overwrite (scanner content is authoritative from the source path).

8. **Run `tree-sitter generate`.** If `config.runGenerate`:
   - Execute `tree-sitter generate` in `<outDir>/`.
   - Capture stdout and stderr.
   - If the process exits with a non-zero code, raise an `ExportError` with the stderr content.
   - After successful generation, verify that `<outDir>/src/parser.c` exists. If not, raise `ExportError`.

```nim
type ExportError* = object of CatchableError
```

### 8.2 File Ownership Rules (Summary)

| File | Ownership detection | Overwrite behavior |
|---|---|---|
| `grammar.js` | Starts with `// Generated by TreeNimph` | Only overwrite owned files |
| `package.json` | `name` field matches `tree-sitter-<grammar>` | Only overwrite owned files |
| `tree-sitter.json` | `grammars[0].name` matches `<grammar>` | Only overwrite owned files |
| Query stubs | Starts with `; Generated by TreeNimph` | Only overwrite owned stubs |
| Query passthrough | N/A (user content) | Always overwrite |
| `src/scanner.c` | N/A (always from source) | Always overwrite |

### 8.3 Idempotency

Running `export` twice with the same `Grammar` object and `ExportConfig` must produce byte-identical files. No timestamps, no random values, no system-dependent content.

---

## 9. Introspection

### 9.1 `renderGrammarJs`

```nim
proc renderGrammarJs*(g: Grammar): string
```

Returns the full `grammar.js` content as a string. Does not write to disk. Does not validate — the caller is responsible for validating first if desired.

### 9.2 `validate`

```nim
proc validate*(g: Grammar): seq[Diagnostic]
```

Returns all diagnostics. Does not raise.

### 9.3 `validateOrRaise`

```nim
proc validateOrRaise*(g: Grammar)
```

Calls `validate`. If any errors exist, raises `ValidationError` with all error diagnostics formatted and joined with newlines.

### 9.4 `summary`

```nim
proc summary*(g: Grammar): string
```

Returns a human-readable multi-line summary.

Format:

```
Grammar: <name> (<n> rules)
Word: <word or "none">
Extras: <count> entries
Conflicts: <count> entries
Supertypes: <names or "none">
Inline: <names or "none">
Externals: <count> entries
Rules:
  <rule1_name>
  <rule2_name>
  ...
```

Hidden rules are listed with their `_` prefix. The rules section lists all rules, one per line, indented with 2 spaces.

---

## 10. Helper Constructors

The helpers module provides reusable constructors for common grammar patterns. All helpers return `Expr` and compose with the core expression types.

### 10.1 `delimitedList`

```nim
proc delimitedList*(item: Expr, sep: Expr, trailing = false): Expr
```

Creates a pattern for one or more items separated by `sep`.

- When `trailing = false`: `seq(item, repeat(seq(sep, item)))`
- When `trailing = true`: `seq(item, repeat(seq(sep, item)), optional(sep))`

Rendered JS (non-trailing):
```javascript
seq(<item>, repeat(seq(<sep>, <item>)))
```

Rendered JS (trailing):
```javascript
seq(<item>, repeat(seq(<sep>, <item>)), optional(<sep>))
```

### 10.2 `optionalDelimitedList`

```nim
proc optionalDelimitedList*(item: Expr, sep: Expr, trailing = false): Expr
```

Like `delimitedList`, but the entire list is optional (zero or more items).

- Returns `optional(delimitedList(item, sep, trailing))`

### 10.3 `balanced`

```nim
proc balanced*(open, close: string, content: Expr): Expr
```

Creates a pattern for balanced delimiters around content.

- Returns `Sequence(Text(open), content, Text(close))`

### 10.4 `keyword`

```nim
proc keyword*(word: string): Expr
```

Creates a `Text` expression. This is a semantic alias — it signals intent that the string is a language keyword rather than punctuation.

- Returns `Text(word)`

---

## 11. Module Structure

```
src/
  treenimph.nim              # Re-exports public API
  treenimph/
    model.nim                # §1 types, §2 constructors, §3 accessors
    validate.nim             # §4 validation
    render_js.nim            # §5 rendering
    render_package.nim       # §6 package metadata rendering
    exporter.nim             # §8 export
    helpers.nim              # §10 helpers
    diagnostics.nim          # §4.5 Diagnostic type and formatting, Levenshtein
```

### 11.1 `treenimph.nim`

Re-exports all public symbols from all submodules. Users write `import treenimph` and get the full API.

### 11.2 Dependency Graph

```
treenimph.nim
  └─ model.nim          (no internal deps)
  └─ diagnostics.nim    (no internal deps)
  └─ validate.nim       (depends on: model, diagnostics)
  └─ render_js.nim      (depends on: model)
  └─ render_package.nim (depends on: model)
  └─ exporter.nim       (depends on: model, validate, render_js, render_package, diagnostics)
  └─ helpers.nim        (depends on: model)
```

No circular dependencies. `model.nim` and `diagnostics.nim` are leaf modules.

---

## 12. Error Types

```nim
type
  ValidationError* = object of CatchableError
    ## Raised by validateOrRaise when validation errors exist.
    diagnostics*: seq[Diagnostic]

  ExportError* = object of CatchableError
    ## Raised by export when file operations or tree-sitter generate fails.
```

---

## 13. Public API Surface

The complete set of public symbols exported by `import treenimph`:

### Types

- `ExprKind`
- `Assoc`
- `Expr`
- `Rule`
- `Grammar`
- `QueryFiles`
- `ExportConfig`
- `DiagnosticKind`
- `Diagnostic`
- `ValidationError`
- `ExportError`

### Expression Constructors

- `Ref`
- `Text`
- `Regex`
- `Blank`
- `Sequence`
- `Choice`
- `Optional`
- `ZeroOrMore`
- `OneOrMore`
- `Field`
- `Alias`
- `Token`
- `ImmediateToken`
- `Prec`
- `PrecLeft`
- `PrecRight`
- `PrecDynamic`

### Model Constructors

- `Rule`
- `Grammar`

### Accessors

- `inner`
- `children`

### Validation

- `validate`
- `validateOrRaise`

### Rendering

- `renderGrammarJs`

### Introspection

- `summary`

### Export

- `export` (proc on `Grammar` taking `ExportConfig`)

### Helpers

- `delimitedList`
- `optionalDelimitedList`
- `balanced`
- `keyword`

### Operators

- `$` for `Diagnostic` (string formatting)

---

## 14. Testing Requirements

This section specifies the minimum test coverage required for each module. Each test case is listed with its purpose. Test names use the format `test_<module>_<description>`.

### 14.1 Model Tests (`test_model.nim`)

#### Constructor tests — one per expression type:

- `test_model_ref_basic`: `Ref("identifier")` produces `ekRef` with `refName == "identifier"`
- `test_model_ref_hidden`: `Ref("_expression")` produces `refName == "_expression"`
- `test_model_text_basic`: `Text("=")` produces `ekText` with `textValue == "="`
- `test_model_regex_basic`: `Regex("[a-z]+")` produces `ekRegex` with `regexPattern == "[a-z]+"`
- `test_model_blank`: `Blank()` produces `ekBlank`
- `test_model_sequence_varargs`: `Sequence(Text("a"), Text("b"), Text("c"))` produces `ekSequence` with 3 items
- `test_model_sequence_empty`: `Sequence()` produces `ekSequence` with 0 items (validation catches this, constructor allows it)
- `test_model_choice_varargs`: `Choice(Ref("a"), Ref("b"))` produces `ekChoice` with 2 items
- `test_model_optional`: `Optional(Ref("x"))` produces `ekOptional` with `item` set
- `test_model_zero_or_more`: `ZeroOrMore(Ref("x"))` produces `ekZeroOrMore`
- `test_model_one_or_more`: `OneOrMore(Ref("x"))` produces `ekOneOrMore`
- `test_model_field`: `Field("name", Ref("x"))` produces `ekField` with correct name and expr
- `test_model_alias_named`: `Alias("foo", Ref("x"))` produces `aliasNamed == true`
- `test_model_alias_anonymous`: `Alias("foo", Ref("x"), named = false)` produces `aliasNamed == false`
- `test_model_token`: `Token(Ref("x"))` produces `ekToken`
- `test_model_immediate_token`: `ImmediateToken(Ref("x"))` produces `ekImmediateToken`
- `test_model_prec_none`: `Prec(5, Ref("x"))` produces `precAssoc == assocNone`, `precLevel == 5`
- `test_model_prec_left`: `PrecLeft(3, Ref("x"))` produces `precAssoc == assocLeft`, `precLevel == 3`
- `test_model_prec_right`: `PrecRight(2, Ref("x"))` produces `precAssoc == assocRight`
- `test_model_prec_dynamic`: `PrecDynamic(1, Ref("x"))` produces `precAssoc == assocDynamic`
- `test_model_prec_negative`: `Prec(-1, Ref("x"))` produces `precLevel == -1`

#### Rule constructor tests:

- `test_model_rule_basic`: `Rule("foo", Ref("bar"))` has `hidden == false`
- `test_model_rule_underscore_auto_hidden`: `Rule("_foo", Ref("bar"))` has `hidden == true`
- `test_model_rule_explicit_hidden`: `Rule("foo", Ref("bar"), hidden = true)` has `hidden == true`
- `test_model_rule_underscore_override`: `Rule("_foo", Ref("bar"), hidden = false)` still has `hidden == true` (underscore forces it)

#### Grammar constructor tests:

- `test_model_grammar_basic`: constructs with name and rules, all optional fields at defaults
- `test_model_grammar_full`: constructs with all fields populated
- `test_model_grammar_varargs_rules`: rules passed as varargs are collected into seq

#### Accessor tests:

- `test_model_inner_optional`: `Optional(Ref("x")).inner` returns the `Ref`
- `test_model_inner_field`: `Field("n", Ref("x")).inner` returns the `Ref`
- `test_model_inner_prec`: `Prec(1, Ref("x")).inner` returns the `Ref`
- `test_model_inner_invalid`: `Ref("x").inner` raises `FieldDefect`
- `test_model_children_sequence`: `Sequence(Ref("a"), Ref("b")).children` returns both refs
- `test_model_children_leaf`: `Ref("a").children` returns empty seq
- `test_model_children_wrapper`: `Optional(Ref("a")).children` returns `@[Ref("a")]`

#### Composition tests:

- `test_model_compose_fragment`: assign expression to variable, use in two different rules
- `test_model_compose_nested`: deeply nested expression tree (Sequence containing Field containing Choice containing Ref)
- `test_model_compose_helper_proc`: define a proc returning Expr, use it in a rule

### 14.2 Validation Tests (`test_validate.nim`)

One test per validation rule (V01–V23), plus edge cases:

- `test_validate_v01_empty_grammar_name`: triggers V01
- `test_validate_v02_invalid_grammar_name`: `"my-lang"` triggers V02, `"my lang"` triggers V02
- `test_validate_v03_no_rules`: triggers V03
- `test_validate_v04_duplicate_rules`: two rules named `"foo"` triggers V04
- `test_validate_v04_duplicate_hidden`: `Rule("foo", ..., hidden=true)` and `Rule("_foo", ...)` are duplicates
- `test_validate_v05_empty_rule_name`: triggers V05
- `test_validate_v06_invalid_rule_name`: `"my rule"` triggers V06
- `test_validate_v07_reserved_prefix_missing`: `"MISSING_foo"` triggers V07
- `test_validate_v07_reserved_prefix_unexpected`: `"UNEXPECTED_foo"` triggers V07
- `test_validate_v08_nil_body`: triggers V08
- `test_validate_v09_undefined_ref`: `Ref("nonexistent")` triggers V09
- `test_validate_v09_undefined_ref_with_hint`: `Ref("identifer")` when `"identifier"` exists produces hint
- `test_validate_v09_ref_to_external`: `Ref` targeting an external does not trigger V09
- `test_validate_v09_ref_to_hidden`: `Ref("_foo")` when `Rule("_foo", ...)` exists does not trigger
- `test_validate_v10_empty_sequence`: triggers V10
- `test_validate_v11_empty_choice`: triggers V11
- `test_validate_v12_invalid_field_name`: `Field("my field", ...)` triggers V12
- `test_validate_v13_invalid_alias_name`: `Alias("123", ..., named = true)` triggers V13
- `test_validate_v14_empty_alias_name`: triggers V14
- `test_validate_v15_nil_child`: `Optional(nil)` triggers V15
- `test_validate_v16_nil_item_in_sequence`: triggers V16
- `test_validate_v17_word_not_found`: `word = some("nonexistent")` triggers V17
- `test_validate_v17_word_with_hint`: `word = some("identifer")` produces hint
- `test_validate_v18_extras_ref_not_found`: triggers V18
- `test_validate_v19_conflicts_ref_not_found`: triggers V19
- `test_validate_v20_supertypes_ref_not_found`: triggers V20
- `test_validate_v21_inline_ref_not_found`: triggers V21
- `test_validate_v22_conflict_too_few`: single-element conflict entry triggers V22
- `test_validate_v23_scanner_not_found`: triggers V23
- `test_validate_valid_grammar`: a complete, valid grammar produces zero diagnostics
- `test_validate_multiple_errors`: a grammar with several issues collects all of them (no short-circuit)
- `test_validate_nested_errors`: errors in deeply nested expression trees include the correct rule name

### 14.3 Renderer Tests (`test_render_js.nim`)

#### Expression-level rendering tests — one per expression type:

- `test_render_ref`: `Ref("identifier")` → `$.identifier`
- `test_render_ref_hidden`: `Ref("_expression")` → `$._expression`
- `test_render_text_simple`: `Text("=")` → `'='`
- `test_render_text_escape_backslash`: `Text("\\")` → `'\\\\'`
- `test_render_text_escape_quote`: `Text("'")` → `'\\''`
- `test_render_text_escape_newline`: `Text("\n")` → `'\\n'`
- `test_render_text_keyword`: `Text("function")` → `'function'`
- `test_render_regex_simple`: `Regex("\\s+")` → `/\\s+/`
- `test_render_regex_escape_slash`: `Regex("a/b")` → `/a\\/b/`
- `test_render_blank`: `Blank()` → `blank()`
- `test_render_sequence_single`: one item sequence
- `test_render_sequence_multi`: multi-item sequence → `seq(...)`
- `test_render_choice`: → `choice(...)`
- `test_render_optional`: → `optional(...)`
- `test_render_zero_or_more`: → `repeat(...)`
- `test_render_one_or_more`: → `repeat1(...)`
- `test_render_field`: → `field('name', ...)`
- `test_render_alias_named`: → `alias(expr, $.name)`
- `test_render_alias_anonymous`: → `alias(expr, 'name')`
- `test_render_token`: → `token(...)`
- `test_render_immediate_token`: → `token.immediate(...)`
- `test_render_prec_none`: → `prec(n, ...)`
- `test_render_prec_left`: → `prec.left(n, ...)`
- `test_render_prec_right`: → `prec.right(n, ...)`
- `test_render_prec_dynamic`: → `prec.dynamic(n, ...)`
- `test_render_prec_negative`: `Prec(-1, ...)` → `prec(-1, ...)`

#### Full grammar rendering tests:

- `test_render_grammar_minimal`: single rule grammar produces valid `grammar.js`
- `test_render_grammar_with_word`: includes `word: $ => $.identifier` section
- `test_render_grammar_with_extras`: includes `extras: $ => [...]` section
- `test_render_grammar_with_conflicts`: includes `conflicts: $ => [...]` section
- `test_render_grammar_with_supertypes`: includes `supertypes: $ => [...]` section
- `test_render_grammar_with_inline`: includes `inline: $ => [...]` section
- `test_render_grammar_with_externals`: includes `externals: $ => [...]` section
- `test_render_grammar_omits_empty_sections`: empty extras/conflicts/etc. are not rendered
- `test_render_grammar_hidden_rule`: rule with `hidden = true` rendered with `_` prefix
- `test_render_grammar_hidden_explicit`: `Rule("foo", ..., hidden=true)` rendered as `_foo`
- `test_render_grammar_header`: output starts with `// Generated by TreeNimph`
- `test_render_grammar_deterministic`: same grammar rendered twice produces identical strings
- `test_render_grammar_trailing_commas`: all array items and object entries have trailing commas
- `test_render_grammar_rule_separation`: rules are separated by blank lines

#### Snapshot tests:

- `test_render_snapshot_json_like`: a JSON-like grammar (object, array, string, number, etc.) compared to expected output
- `test_render_snapshot_expression_lang`: the example grammar from the concept doc compared to expected output

### 14.4 Package Metadata Tests (`test_render_package.nim`)

- `test_render_package_json_structure`: output is valid JSON with required keys
- `test_render_package_json_name`: `"name"` is `"tree-sitter-<grammar_name>"`
- `test_render_package_json_keywords`: includes `"tree-sitter"` and grammar name
- `test_render_tree_sitter_json_structure`: output is valid JSON with required keys
- `test_render_tree_sitter_json_grammar_name`: `grammars[0].name` matches grammar name
- `test_render_tree_sitter_json_scope`: `grammars[0].scope` is `"source.<grammar_name>"`

### 14.5 Export Tests (`test_export.nim`)

These tests use temporary directories.

- `test_export_creates_directory_structure`: export creates `outDir/`, `outDir/queries/`, `outDir/src/`
- `test_export_writes_grammar_js`: `grammar.js` exists and starts with header
- `test_export_writes_package_json`: `package.json` exists and is valid JSON
- `test_export_writes_tree_sitter_json`: `tree-sitter.json` exists and is valid JSON
- `test_export_writes_query_stubs`: all four `.scm` files exist when `writeQueryStubs = true`
- `test_export_skips_query_stubs`: no `.scm` files when `writeQueryStubs = false` and no `queryFiles`
- `test_export_writes_query_passthrough`: `queryFiles` content written verbatim
- `test_export_copies_scanner`: `src/scanner.c` exists when `scannerPath` is set
- `test_export_validates_first`: invalid grammar raises `ValidationError`, no files written
- `test_export_idempotent`: two exports produce identical files
- `test_export_refuses_overwrite_user_file`: raises error when `grammar.js` exists without TreeNimph header
- `test_export_overwrites_own_file`: overwrites `grammar.js` that has TreeNimph header
- `test_export_no_overwrite_mode`: raises error when file exists and `overwrite = false`

### 14.6 Helper Tests (`test_helpers.nim`)

- `test_helper_delimited_list_basic`: `delimitedList(Ref("x"), Text(","))` produces correct structure
- `test_helper_delimited_list_trailing`: `delimitedList(Ref("x"), Text(","), trailing = true)` includes `optional(",")`
- `test_helper_optional_delimited_list`: `optionalDelimitedList(...)` wraps in `Optional`
- `test_helper_balanced`: `balanced("(", ")", Ref("x"))` produces `Sequence(Text("("), Ref("x"), Text(")"))`
- `test_helper_keyword`: `keyword("return")` produces `Text("return")`
- `test_helper_delimited_list_renders`: rendered output matches expected JS

### 14.7 Diagnostic Tests (`test_diagnostics.nim`)

- `test_diagnostic_format_error_only`: error with message only
- `test_diagnostic_format_with_rule`: error with rule name
- `test_diagnostic_format_with_hint`: error with hint
- `test_diagnostic_format_with_both`: error with rule name and hint
- `test_diagnostic_format_warning`: warning formatting
- `test_diagnostic_levenshtein_exact`: distance 0 for identical strings
- `test_diagnostic_levenshtein_one_char`: distance 1 for single character difference
- `test_diagnostic_levenshtein_transposition`: handles common typos
- `test_diagnostic_did_you_mean`: suggests closest match within distance 2
- `test_diagnostic_no_suggestion`: no suggestion when all names are distance > 2

### 14.8 Integration Tests (`test_examples.nim`)

These tests verify end-to-end behavior by constructing real grammars and verifying the full pipeline.

- `test_example_minimal`: single-rule grammar → validate → render → verify output
- `test_example_json_like`: JSON-like grammar with objects, arrays, strings, numbers → full export → verify all files
- `test_example_expression_lang`: expression language with precedence, fields, tokens → full export → verify output
- `test_example_composability`: grammar built with reusable fragments and helpers → verify output matches equivalent grammar built inline
- `test_example_with_externals`: grammar with externals → verify externals section in rendered JS
- `test_example_with_scanner`: grammar with scanner passthrough → verify scanner copied

If `tree-sitter` CLI is available (detected at test start):
- `test_example_tree_sitter_generate`: export → run `tree-sitter generate` → verify `src/parser.c` exists

---

## 15. Levenshtein Distance

The `diagnostics` module implements Levenshtein distance for "did you mean" suggestions.

```nim
proc levenshteinDistance*(a, b: string): int
```

Standard dynamic programming implementation. Case-sensitive comparison.

```nim
proc findClosestMatch*(target: string, candidates: seq[string], maxDistance = 2): Option[string]
```

Returns the candidate with the smallest Levenshtein distance to `target`, if that distance is ≤ `maxDistance`. On ties, returns the candidate that appears first in the seq.

---

## 16. Edge Cases and Constraints

### 16.1 Expr Identity

Expressions are `ref` objects. Two `Ref("foo")` calls produce two distinct objects. Comparing expressions for equality is pointer comparison unless `==` is explicitly defined. TreeNimph v1 does **not** define `==` for `Expr`. Expressions are compared by structure only during validation, not by identity.

### 16.2 Shared Expression Instances

Because expressions are `ref` objects, a single `Expr` instance can be referenced from multiple places in the tree:

```nim
let id = Ref("identifier")
let r1 = Rule("a", Sequence(id, Text("=")))
let r2 = Rule("b", Sequence(id, Text("+")))
```

This is valid and supported. The renderer traverses expressions by value, not by identity. No expression is modified during rendering or validation.

### 16.3 Grammar Name Constraints

- Must match `^[a-zA-Z_][a-zA-Z0-9_]*$`
- Must not be empty
- Used to derive package name (`tree-sitter-<name>`), scope (`source.<name>`), and various identifiers

### 16.4 Rule Ordering

The first rule in `grammar.rules` is the start rule. This is a Tree-sitter requirement. TreeNimph preserves rule order exactly as given.

### 16.5 Canonical Names and Refs

Ref names are stored and rendered verbatim. If a user writes `Ref("expression")` to reference a rule defined as `Rule("expression", ..., hidden = true)`, this is a validation error — the canonical name is `_expression`, and the ref must use `Ref("_expression")`.

Conversely, if a user writes `Rule("_expression", ...)`, the rule's canonical name is `_expression`, and refs must use `Ref("_expression")`.

The Rule constructor's behavior:
- `Rule("_foo", body)` → `name = "_foo"`, `hidden = true`
- `Rule("foo", body, hidden = true)` → `name = "foo"`, `hidden = true`, rendered as `_foo`

For validation and ref resolution, the canonical name of a rule is:
- If `hidden == true` and `name` does not start with `_`: canonical = `"_" & name`
- Otherwise: canonical = `name`

Refs are checked against the canonical name set.

### 16.6 Externals and Ref Resolution

Expressions in `grammar.externals` can be `Ref` expressions. The names from these externals are added to the valid reference set for ref resolution. This means rules can reference externals that do not have corresponding `Rule` definitions — they are provided by the external scanner.

External refs are collected by walking `grammar.externals` and collecting all `Ref` names found.
