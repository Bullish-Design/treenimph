import std/[os, osproc, strutils, tempfiles]
import unittest

const srcFlag = "-p:src"

proc compileAndRun(code: string, args: string = ""): tuple[output: string, exitCode: int] =
  let (tmpFile, tmpPath) = createTempFile("treenimph_dsl_test_", ".nim")
  tmpFile.write(code)
  tmpFile.close()
  defer: removeFile(tmpPath)

  let cmd = "nim r --hints:off " & srcFlag & " " & tmpPath & " " & args
  execCmdEx(cmd)

suite "DSL integration — simple grammars":
  test "minimal grammar produces valid grammar.js":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "minimal":
  source = re"[a-z]+"
""")
    check code == 0
    check output.contains("module.exports = grammar")
    check output.contains("'minimal'")
    check output.contains("source: $ =>")

  test "grammar with sequences and choices":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "test_lang":
  source = *statement
  statement = let_stmt | expr_stmt
  let_stmt = ["let", name@identifier, "=", value@expression, ";"]
  expr_stmt = [expression, ";"]
  expression = identifier | number
  identifier = re"[a-zA-Z_][a-zA-Z0-9_]*"
  number = re"[0-9]+"
""")
    check code == 0
    check output.contains("module.exports = grammar")
    check output.contains("'test_lang'")
    check output.contains("repeat($.statement)")
    check output.contains("choice($.let_stmt, $.expr_stmt)")
    check output.contains("field('name', $.identifier)")
    check output.contains("'let'")
    check output.contains("';'")

  test "grammar with let bindings":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "json":
  extras = [re"\\s+"]

  let value = val_node
  let comma = ","

  document = value
  val_node = obj_rule | string_rule | number_rule
  obj_rule = ["{", ?delimitedList(pair, comma, trailing = true), "}"]
  pair = [key@string_rule, ":", val@value]
  string_rule = re"[a-zA-Z_]+"
  number_rule = re"[0-9]+"
""")
    check code == 0
    check output.contains("module.exports = grammar")
    check output.contains("extras: $ => [")

  test "grammar with precedence":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "arith":
  expression = number | binary_expression
  binary_expression = prec_left(1, [left@expression, operator@("+" | "-"), right@expression])
  number = re"[0-9]+"
""")
    check code == 0
    check output.contains("prec.left(1")
    check output.contains("field('left'")
    check output.contains("field('operator'")

suite "DSL integration — CLI flags":
  test "--summary flag":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "demo":
  source = "x"
""", "--summary")
    check code == 0
    check output.contains("Grammar: demo")

  test "--validate flag":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "demo":
  source = "x"
""", "--validate")
    check code == 0
    check output.contains("valid")

  test "--export flag":
    let tmpDir = createTempDir("treenimph_dsl_export_", "")
    defer: removeDir(tmpDir)

    let exportDir = tmpDir / "output"
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "exported":
  source = *statement
  statement = "x"
""", "--export " & exportDir)
    check code == 0
    check fileExists(exportDir / "grammar.js")
    check fileExists(exportDir / "package.json")
    check fileExists(exportDir / "tree-sitter.json")

suite "DSL integration — grammar config sections":
  test "word, extras, supertypes, inline, conflicts":
    let (output, code) = compileAndRun("""
import treenimph/dsl

grammar "full_config":
  extras = [re"\\s+"]
  word = identifier
  supertypes = [expression_node]
  inline = [helper_rule]
  conflicts = [[expression_node, binary_expression]]

  source = *expression_node
  expression_node = identifier | binary_expression
  binary_expression = prec_left(1, [expression_node, "+", expression_node])
  identifier = re"[a-zA-Z_]+"
  helper_rule = re"\\s+"
""")
    check code == 0
    check output.contains("word: $ => $.identifier")
    check output.contains("extras: $ => [")
    check output.contains("supertypes: $ => [")
    check output.contains("inline: $ => [")
    check output.contains("conflicts: $ => [")
