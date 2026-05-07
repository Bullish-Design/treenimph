import std/[os, osproc]
import unittest

import fixture_utils

const srcFlag = "-p:src"
const nimNoiseFlags = "--hints:off --warnings:off"
const casesDir = "tests/fixtures/dsl_errors/cases"

proc checkCase(caseName: string) =
  let cmd = "nim check " & nimNoiseFlags & " " & srcFlag & " " & (casesDir / (caseName & ".nim"))
  let (output, code) = execCmdEx(cmd)
  check code != 0
  assertMatchesFixture(output, fixturePath("fixtures", "dsl_errors", "expected", caseName & ".stderr"))

suite "DSL compile-time errors fixtures":
  test "empty grammar body fails":
    checkCase("empty_grammar")

  test "@ with non-identifier LHS fails":
    checkCase("bad_field")

  test "empty brackets fail":
    checkCase("bad_sequence")

  test "prec_left with missing args fails":
    checkCase("bad_prec")
