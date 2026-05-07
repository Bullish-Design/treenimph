import std/options
import std/strutils
import unittest

import treenimph/diagnostics

suite "Diagnostic formatting":
  test "error format with metadata":
    let d = error("bad ref", some("source"), some("fix spelling"))
    check $d == "Error: bad ref\n  In rule \"source\"\n  Hint: fix spelling"

  test "warning format":
    let d = warning("unused")
    check $d == "Warning: unused"

suite "Levenshtein":
  test "distance basics":
    check levenshteinDistance("kitten", "sitting") == 3
    check levenshteinDistance("", "abc") == 3
    check levenshteinDistance("abc", "") == 3
    check levenshteinDistance("abc", "abc") == 0

  test "closest match found":
    let m = findClosestMatch("sourc", @["source", "expr"])
    check m.isSome
    check m.get == "source"

  test "closest match none":
    let m = findClosestMatch("zzzz", @["source", "expr"], maxDistance = 1)
    check m.isNone

suite "ValidationError":
  test "newValidationError carries diagnostics":
    let diags = @[error("one"), error("two")]
    let e = newValidationError(diags)
    check e.diagnostics.len == 2
    check e.msg.contains("Error: one")
    check e.msg.contains("Error: two")
