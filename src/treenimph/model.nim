import std/[options, strutils]

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

proc mkRule*(name: string, body: Expr, hidden = false): Rule =
  var h = hidden
  if name.len > 0 and name[0] == '_':
    h = true
  Rule(name: name, body: body, hidden: h)

proc mkGrammar*(
  name: string,
  rules: openArray[Rule],
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

proc mkExportConfig*(
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

proc inner*(e: Expr): Expr =
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

proc canonicalName*(r: Rule): string =
  if r.hidden and r.name.len > 0 and r.name[0] != '_':
    "_" & r.name
  else:
    r.name

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
