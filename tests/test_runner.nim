import std/[osproc, strutils, os]
import unittest

const examplesDir = "examples"
const srcFlag = "-p:src"

proc runGrammar(file: string, args: string = ""): tuple[output: string, exitCode: int] =
  ## Compile and run a grammar file, returning stdout+stderr and exit code.
  let cmd = "nim r --hints:off " & srcFlag & " " & (examplesDir / file) & " " & args
  execCmdEx(cmd)

suite "runner — default action (print grammar.js)":
  test "simple_lang prints grammar.js":
    let (output, code) = runGrammar("simple_lang.nim")
    check code == 0
    check output.contains("module.exports = grammar")
    check output.contains("simple_lang")

  test "arithmetic prints grammar.js":
    let (output, code) = runGrammar("arithmetic.nim")
    check code == 0
    check output.contains("module.exports = grammar")

  test "json_like prints grammar.js":
    let (output, code) = runGrammar("json_like.nim")
    check code == 0
    check output.contains("module.exports = grammar")

suite "runner — --summary":
  test "simple_lang summary":
    let (output, code) = runGrammar("simple_lang.nim", "--summary")
    check code == 0
    check output.contains("Grammar: simple_lang")
    check output.contains("rules")

suite "runner — --validate":
  test "simple_lang validates":
    let (output, code) = runGrammar("simple_lang.nim", "--validate")
    check code == 0
    check output.contains("valid")

suite "runner — --export":
  test "simple_lang exports to temp dir":
    let tmpDir = getTempDir() / "treenimph_runner_test"
    removeDir(tmpDir)
    defer: removeDir(tmpDir)

    let (output, code) = runGrammar("simple_lang.nim", "--export " & tmpDir)
    check code == 0
    check fileExists(tmpDir / "grammar.js")
    check fileExists(tmpDir / "package.json")
    check fileExists(tmpDir / "tree-sitter.json")
    check dirExists(tmpDir / "queries")
