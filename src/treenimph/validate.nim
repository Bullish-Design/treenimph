import std/[options, os, sets, strutils, tables]

import ./diagnostics
import ./model

proc isValidIdentifier(s: string): bool =
  if s.len == 0:
    return false
  if s[0] notin {'a'..'z', 'A'..'Z', '_'}:
    return false
  for i in 1..<s.len:
    if s[i] notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
      return false
  true

proc isValidRuleName(s: string): bool =
  if s.len == 0:
    return false
  var start = 0
  if s[0] == '_':
    start = 1
    if start >= s.len:
      return false
  if s[start] notin {'a'..'z', 'A'..'Z', '_'}:
    return false
  for i in (start + 1)..<s.len:
    if s[i] notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}:
      return false
  true

proc collectExternalRefs(externals: seq[Expr], names: var HashSet[string]) =
  for e in externals:
    if e != nil and e.kind == ekRef:
      names.incl e.refName

proc validateGrammarLevel(g: Grammar, diags: var seq[Diagnostic]) =
  if g.name.len == 0:
    diags.add error("Grammar name must not be empty")
  elif not isValidIdentifier(g.name):
    diags.add error("Grammar name \"" & g.name & "\" is not a valid identifier")

  if g.rules.len == 0:
    diags.add error("Grammar must define at least one rule")

proc buildRuleNameSet(
  g: Grammar,
  ruleNames: var HashSet[string],
  ruleNameList: var seq[string],
  rulePositions: var Table[string, int],
  diags: var seq[Diagnostic],
) =
  for i, rule in g.rules:
    let pos = i + 1
    if rule.name.len == 0:
      diags.add error("Rule name must not be empty", hint = some("Rule #" & $pos))
      continue

    let cname = rule.canonicalName

    if not isValidRuleName(cname):
      diags.add error("Rule name \"" & cname & "\" is not a valid identifier", ruleName = some(cname))

    if cname.startsWith("MISSING") or cname.startsWith("UNEXPECTED") or
        (cname.len > 1 and cname[0] == '_' and
        (cname[1..^1].startsWith("MISSING") or cname[1..^1].startsWith("UNEXPECTED"))):
      diags.add error(
        "Rule name \"" & cname & "\" uses a reserved prefix",
        ruleName = some(cname),
        hint = some("Tree-sitter reserves names starting with \"MISSING\" and \"UNEXPECTED\""),
      )

    if cname in ruleNames:
      let firstPos = rulePositions[cname]
      diags.add error(
        "Duplicate rule name \"" & cname & "\"",
        ruleName = some(cname),
        hint = some("First defined as rule #" & $firstPos & ", redefined as rule #" & $pos),
      )
    else:
      ruleNames.incl cname
      ruleNameList.add cname
      rulePositions[cname] = pos

    if rule.body == nil:
      diags.add error("Rule \"" & cname & "\" has a nil body", ruleName = some(cname))

proc validateExprTree(
  e: Expr,
  ruleName: string,
  validRefs: HashSet[string],
  ruleNameList: seq[string],
  diags: var seq[Diagnostic],
) =
  if e == nil:
    return

  case e.kind
  of ekRef:
    if e.refName notin validRefs:
      var d = error(
        "Unknown rule reference \"" & e.refName & "\" in rule \"" & ruleName & "\"",
        ruleName = some(ruleName),
      )
      let suggestion = findClosestMatch(e.refName, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

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

  of ekField:
    if not isValidIdentifier(e.fieldName):
      diags.add error("Invalid field name \"" & e.fieldName & "\" in rule \"" & ruleName & "\"", ruleName = some(ruleName))
    if e.fieldExpr == nil:
      diags.add error("Field has a nil child expression in rule \"" & ruleName & "\"", ruleName = some(ruleName))

  of ekAlias:
    if e.aliasName.len == 0:
      diags.add error("Alias name must not be empty in rule \"" & ruleName & "\"", ruleName = some(ruleName))
    elif e.aliasNamed and not isValidRuleName(e.aliasName):
      diags.add error(
        "Invalid alias name \"" & e.aliasName & "\" in rule \"" & ruleName & "\"",
        ruleName = some(ruleName),
        hint = some("Named aliases must be valid identifiers"),
      )
    if e.aliasExpr == nil:
      diags.add error("Alias has a nil child expression in rule \"" & ruleName & "\"", ruleName = some(ruleName))

  of ekOptional:
    if e.item == nil:
      diags.add error("Optional has a nil child expression in rule \"" & ruleName & "\"", ruleName = some(ruleName))

  of ekZeroOrMore:
    if e.item == nil:
      diags.add error("ZeroOrMore has a nil child expression in rule \"" & ruleName & "\"", ruleName = some(ruleName))

  of ekOneOrMore:
    if e.item == nil:
      diags.add error("OneOrMore has a nil child expression in rule \"" & ruleName & "\"", ruleName = some(ruleName))

  of ekToken:
    if e.tokenExpr == nil:
      diags.add error("Token has a nil child expression in rule \"" & ruleName & "\"", ruleName = some(ruleName))

  of ekImmediateToken:
    if e.tokenExpr == nil:
      diags.add error("ImmediateToken has a nil child expression in rule \"" & ruleName & "\"", ruleName = some(ruleName))

  of ekPrecedence:
    if e.precExpr == nil:
      diags.add error("Prec has a nil child expression in rule \"" & ruleName & "\"", ruleName = some(ruleName))

  of ekText, ekRegex, ekBlank:
    discard

  for child in e.children:
    if child != nil:
      validateExprTree(child, ruleName, validRefs, ruleNameList, diags)

proc validateGrammarConfig(
  g: Grammar,
  ruleNames: HashSet[string],
  ruleNameList: seq[string],
  diags: var seq[Diagnostic],
) =
  if g.word.isSome:
    let w = g.word.get
    if w notin ruleNames:
      var d = error("Word rule \"" & w & "\" does not exist")
      let suggestion = findClosestMatch(w, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

  for expr in g.extras:
    if expr != nil and expr.kind == ekRef and expr.refName notin ruleNames:
      var d = error("Extras reference \"" & expr.refName & "\" does not match any rule")
      let suggestion = findClosestMatch(expr.refName, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

  for conflict in g.conflicts:
    if conflict.len < 2:
      diags.add error("Conflict entry must contain at least 2 rule names")
    for name in conflict:
      if name notin ruleNames:
        var d = error("Conflict reference \"" & name & "\" does not match any rule")
        let suggestion = findClosestMatch(name, ruleNameList)
        if suggestion.isSome:
          d.hint = some("Did you mean \"" & suggestion.get & "\"?")
        diags.add d

  for name in g.supertypes:
    if name notin ruleNames:
      var d = error("Supertype \"" & name & "\" does not match any rule")
      let suggestion = findClosestMatch(name, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

  for name in g.inline:
    if name notin ruleNames:
      var d = error("Inline rule \"" & name & "\" does not match any rule")
      let suggestion = findClosestMatch(name, ruleNameList)
      if suggestion.isSome:
        d.hint = some("Did you mean \"" & suggestion.get & "\"?")
      diags.add d

  if g.scannerPath.isSome:
    let path = g.scannerPath.get
    if not fileExists(path):
      diags.add error("Scanner file \"" & path & "\" does not exist")

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
  for e in g.extras:
    collectReferencedNames(e, referencedNames)
  for e in g.externals:
    collectReferencedNames(e, referencedNames)
  for i in 1..<g.rules.len:
    let cname = g.rules[i].canonicalName
    if cname notin referencedNames:
      diags.add warning(
        "Rule \"" & cname & "\" is never referenced by any other rule",
        ruleName = some(cname),
        hint = some("This may indicate dead code or a missing reference"),
      )

proc validate*(g: Grammar): seq[Diagnostic] =
  var diags: seq[Diagnostic] = @[]

  validateGrammarLevel(g, diags)

  var ruleNames: HashSet[string]
  var ruleNameList: seq[string]
  var rulePositions: Table[string, int]
  buildRuleNameSet(g, ruleNames, ruleNameList, rulePositions, diags)

  var externalNames: HashSet[string]
  collectExternalRefs(g.externals, externalNames)
  let validRefs = ruleNames + externalNames

  for rule in g.rules:
    if rule.body != nil:
      validateExprTree(rule.body, rule.canonicalName, validRefs, ruleNameList, diags)

  validateGrammarConfig(g, ruleNames, ruleNameList, diags)
  warnUnreferencedRules(g, diags)

  diags

proc validateOrRaise*(g: Grammar) =
  let diags = g.validate()
  var errors: seq[Diagnostic] = @[]
  for d in diags:
    if d.kind == dkError:
      errors.add d
  if errors.len > 0:
    raise newValidationError(errors)
