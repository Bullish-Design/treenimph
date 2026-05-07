version       = "0.1.0"
author        = "TreeNimph Contributors"
description   = "A Nim library for authoring Tree-sitter grammars as composable typed objects"
license       = "MIT"
srcDir        = "src"
bin           = @["treenimph"]

requires "nim >= 2.0.0"

task test, "Run all tests":
  for f in listFiles("tests"):
    if f.endsWith(".nim"):
      exec "nim r -p:src " & f
