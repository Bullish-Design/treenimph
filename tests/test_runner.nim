import std/[osproc, os]
import unittest

import fixture_utils

const examplesDir = "examples"
const srcFlag = "-p:src"
const nimNoiseFlags = "--hints:off --warnings:off"

proc runGrammar(file: string, args: string = ""): tuple[output: string, exitCode: int] =
  let cmd = "nim r " & nimNoiseFlags & " " & srcFlag & " " & (examplesDir / file) & " " & args
  execCmdEx(cmd)

suite "runner fixtures — default action":
  test "simple_lang grammar.js snapshot":
    let (output, code) = runGrammar("simple_lang.nim")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "runner", "simple_lang", "default.stdout"))

  test "arithmetic grammar.js snapshot":
    let (output, code) = runGrammar("arithmetic.nim")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "runner", "arithmetic", "default.stdout"))

  test "json_like grammar.js snapshot":
    let (output, code) = runGrammar("json_like.nim")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "runner", "json_like", "default.stdout"))

suite "runner fixtures — summary/validate":
  test "simple_lang summary snapshot":
    let (output, code) = runGrammar("simple_lang.nim", "--summary")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "runner", "simple_lang", "summary.stdout"))

  test "simple_lang validate snapshot":
    let (output, code) = runGrammar("simple_lang.nim", "--validate")
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "runner", "simple_lang", "validate.stdout"))

suite "runner fixtures — export":
  test "simple_lang export output and files":
    let tmpDir = getTempDir() / "treenimph_runner_test"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    let (output, code) = runGrammar("simple_lang.nim", "--export " & tmpDir)
    check code == 0
    assertMatchesFixture(output, fixturePath("fixtures", "runner", "simple_lang", "export.stdout"))

    check fileExists(tmpDir / "grammar.js")
    check fileExists(tmpDir / "package.json")
    check fileExists(tmpDir / "tree-sitter.json")
    check dirExists(tmpDir / "queries")

    let exportedGrammarJs = readFile(tmpDir / "grammar.js")
    assertMatchesFixture(exportedGrammarJs, fixturePath("fixtures", "runner", "simple_lang", "exported_grammar.js"))
