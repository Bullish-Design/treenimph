import std/[os, osproc]
import unittest

import fixture_utils

const srcFlag = "-p:src"
const nimNoiseFlags = "--hints:off --warnings:off"
const casesDir = "tests/fixtures/dsl_integration/cases"

proc runCase(caseName: string, args: string = ""): tuple[output: string, exitCode: int] =
  let cmd = "nim r " & nimNoiseFlags & " " & srcFlag & " " & (casesDir / (caseName & ".nim")) & " " & args
  execCmdEx(cmd)

suite "DSL integration fixtures — simple grammars":
  test "minimal grammar grammar.js snapshot":
    let (output, code) = runCase("minimal")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "dsl_integration", "expected", "minimal.default.stdout"))

  test "sequences and choices grammar.js snapshot":
    let (output, code) = runCase("sequences_and_choices")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "dsl_integration", "expected", "sequences_and_choices.default.stdout"))

  test "let bindings grammar.js snapshot":
    let (output, code) = runCase("let_bindings")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "dsl_integration", "expected", "let_bindings.default.stdout"))

  test "precedence grammar.js snapshot":
    let (output, code) = runCase("precedence")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "dsl_integration", "expected", "precedence.default.stdout"))

suite "DSL integration fixtures — CLI flags":
  test "--summary snapshot":
    let (output, code) = runCase("demo", "--summary")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "dsl_integration", "expected", "demo.summary.stdout"))

  test "--validate snapshot":
    let (output, code) = runCase("demo", "--validate")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "dsl_integration", "expected", "demo.validate.stdout"))

  test "--export snapshot and files":
    let tmpDir = getTempDir() / "treenimph_dsl_export_fixture"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    let exportDir = tmpDir / "output"
    let (output, code) = runCase("exported", "--export " & exportDir)
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "dsl_integration", "expected", "exported.export.stdout"))

    check fileExists(exportDir / "grammar.js")
    check fileExists(exportDir / "package.json")
    check fileExists(exportDir / "tree-sitter.json")

    let exportedGrammarJs = readFile(exportDir / "grammar.js")
    assertMatchesFixture(exportedGrammarJs, fixturePath("fixtures", "dsl_integration", "expected", "exported.exported_grammar.js"))

suite "DSL integration fixtures — grammar config":
  test "full config grammar.js snapshot":
    let (output, code) = runCase("full_config")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "dsl_integration", "expected", "full_config.default.stdout"))
