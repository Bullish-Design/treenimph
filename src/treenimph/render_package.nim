import std/[json, options]

import ./model

proc renderPackageJson*(g: Grammar): string =
  let j = %*{
    "name": "tree-sitter-" & g.name,
    "version": "0.1.0",
    "description": g.name & " grammar for tree-sitter",
    "main": "bindings/node",
    "types": "bindings/node",
    "keywords": [
      "incremental",
      "parsing",
      "tree-sitter",
      g.name,
    ],
    "files": [
      "grammar.js",
      "tree-sitter.json",
      "binding.gyp",
      "prebuilds/**",
      "bindings/node/*",
      "queries/*",
      "src/**",
      "*.wasm",
    ],
    "dependencies": {
      "node-addon-api": "^8.2.2",
      "node-gyp-build": "^4.8.2",
    },
    "devDependencies": {
      "tree-sitter-cli": "^0.25.0",
    },
    "peerDependencies": {
      "tree-sitter": "^0.22.0",
    },
    "peerDependenciesMeta": {
      "tree-sitter": {
        "optional": true,
      },
    },
    "scripts": {
      "install": "node-gyp-build",
      "prestart": "tree-sitter build --wasm",
      "start": "tree-sitter playground",
      "test": "tree-sitter test",
    },
  }
  pretty(j, indent = 2) & "\n"

proc renderTreeSitterJson*(g: Grammar, writeQueryStubs = true): string =
  var grammarEntry = %*{
    "name": g.name,
    "scope": "source." & g.name,
    "path": ".",
  }

  grammarEntry["file-types"] = newJArray()

  let qf = if g.queryFiles.isSome: g.queryFiles.get else: QueryFiles()

  if qf.highlights.isSome or writeQueryStubs:
    grammarEntry["highlights"] = %"queries/highlights.scm"
  if qf.tags.isSome or writeQueryStubs:
    grammarEntry["tags"] = %"queries/tags.scm"
  if qf.locals.isSome or writeQueryStubs:
    grammarEntry["locals"] = %"queries/locals.scm"
  if qf.injections.isSome or writeQueryStubs:
    grammarEntry["injections"] = %"queries/injections.scm"

  let j = %*{
    "grammars": [grammarEntry],
    "metadata": {
      "version": "0.1.0",
      "description": g.name & " grammar for tree-sitter",
      "links": newJObject(),
    },
    "bindings": {
      "c": true,
      "go": true,
      "node": true,
      "python": true,
      "rust": true,
      "swift": true,
    },
  }
  pretty(j, indent = 2) & "\n"
