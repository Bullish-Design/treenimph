import std/options

type
  DiagnosticKind* = enum
    dkError
    dkWarning

  Diagnostic* = object
    kind*: DiagnosticKind
    message*: string
    ruleName*: Option[string]
    hint*: Option[string]

  ValidationError* = object of CatchableError
    diagnostics*: seq[Diagnostic]

  ExportError* = object of CatchableError

proc `$`*(d: Diagnostic): string =
  let prefix = case d.kind
    of dkError: "Error"
    of dkWarning: "Warning"
  result = prefix & ": " & d.message
  if d.ruleName.isSome:
    result.add "\n  In rule \"" & d.ruleName.get & "\""
  if d.hint.isSome:
    result.add "\n  Hint: " & d.hint.get

proc error*(message: string, ruleName = none(string), hint = none(string)): Diagnostic =
  Diagnostic(kind: dkError, message: message, ruleName: ruleName, hint: hint)

proc warning*(message: string, ruleName = none(string), hint = none(string)): Diagnostic =
  Diagnostic(kind: dkWarning, message: message, ruleName: ruleName, hint: hint)

proc levenshteinDistance*(a, b: string): int =
  let
    m = a.len
    n = b.len

  if m == 0:
    return n
  if n == 0:
    return m

  var dp = newSeq[seq[int]](m + 1)
  for i in 0..m:
    dp[i] = newSeq[int](n + 1)
    dp[i][0] = i
  for j in 0..n:
    dp[0][j] = j

  for i in 1..m:
    for j in 1..n:
      let cost = if a[i - 1] == b[j - 1]: 0 else: 1
      dp[i][j] = min(
        dp[i - 1][j] + 1,
        min(
          dp[i][j - 1] + 1,
          dp[i - 1][j - 1] + cost
        )
      )

  dp[m][n]

proc findClosestMatch*(target: string, candidates: seq[string], maxDistance = 2): Option[string] =
  var bestDist = maxDistance + 1
  var bestMatch = ""
  for c in candidates:
    let d = levenshteinDistance(target, c)
    if d < bestDist:
      bestDist = d
      bestMatch = c
  if bestDist <= maxDistance:
    some(bestMatch)
  else:
    none(string)

proc newValidationError*(diagnostics: seq[Diagnostic]): ref ValidationError =
  var msg = ""
  for d in diagnostics:
    if msg.len > 0:
      msg.add "\n\n"
    msg.add $d
  result = newException(ValidationError, msg)
  result.diagnostics = diagnostics
