import std/[json]
import unittest

import treenimph/[model, render_package]

suite "render_package":
  test "renderPackageJson includes grammar name":
    let g = mkGrammar("demo", rules = [mkRule("source", Blank())])
    let s = g.renderPackageJson()
    let j = parseJson(s)
    check j["name"].getStr == "tree-sitter-demo"

  test "renderTreeSitterJson writes query stubs by default":
    let g = mkGrammar("demo", rules = [mkRule("source", Blank())])
    let s = g.renderTreeSitterJson()
    let j = parseJson(s)
    check j["grammars"][0].hasKey("highlights")
    check j["grammars"][0].hasKey("tags")

  test "renderTreeSitterJson omits query fields when disabled":
    let g = mkGrammar("demo", rules = [mkRule("source", Blank())])
    let s = g.renderTreeSitterJson(writeQueryStubs = false)
    let j = parseJson(s)
    check not j["grammars"][0].hasKey("highlights")
