import std/[os, tempfiles]
import unittest

import treenimph/[diagnostics, exporter, model]

suite "exporter":
  test "export creates directory structure":
    let tmpDir = createTempDir("treenimph_test_", "")
    defer: removeDir(tmpDir)

    let outDir = tmpDir / "output"
    let g = mkGrammar("test", rules = [mkRule("source", Blank())])
    g.exportGrammar(mkExportConfig(outDir))

    check dirExists(outDir)
    check dirExists(outDir / "queries")
    check dirExists(outDir / "src")
    check fileExists(outDir / "grammar.js")
    check fileExists(outDir / "package.json")
    check fileExists(outDir / "tree-sitter.json")

  test "export fails on invalid grammar":
    let tmpDir = createTempDir("treenimph_test_", "")
    defer: removeDir(tmpDir)

    let g = mkGrammar("test", rules = [mkRule("source", Ref("missing"))])
    expect ValidationError:
      g.exportGrammar(mkExportConfig(tmpDir / "out"))

  test "export can overwrite owned files":
    let tmpDir = createTempDir("treenimph_test_", "")
    defer: removeDir(tmpDir)

    let outDir = tmpDir / "output"
    let g = mkGrammar("test", rules = [mkRule("source", Blank())])
    g.exportGrammar(mkExportConfig(outDir))
    g.exportGrammar(mkExportConfig(outDir, overwrite = true))
    check fileExists(outDir / "grammar.js")
