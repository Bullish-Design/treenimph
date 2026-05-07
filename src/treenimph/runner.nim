import std/[os, parseopt, strutils]

import ./diagnostics
import ./exporter
import ./model
import ./render_js
import ./validate

type
  RunAction = enum
    raPrintJs
    raSummary
    raValidate
    raExport

proc run*(g: Grammar) =
  ## Entry point for grammar files. Validates the grammar, parses CLI
  ## arguments, and dispatches the requested action.
  ##
  ## CLI options:
  ##   (no options)        Print grammar.js to stdout
  ##   --export <dir>      Export full tree-sitter package to directory
  ##   --summary           Print grammar summary
  ##   --validate          Validate only (exit 0 = clean, exit 1 = errors)
  ##   --overwrite         Allow overwriting existing files (with --export)
  ##   --run-generate      Run tree-sitter generate after export (with --export)
  ##   --no-query-stubs    Skip generating empty query stubs (with --export)

  let diags = g.validate()
  var hasErrors = false
  for d in diags:
    if d.kind == dkError:
      hasErrors = true
      stderr.writeLine $d
    elif d.kind == dkWarning:
      stderr.writeLine $d

  if hasErrors:
    quit(1)

  var action = raPrintJs
  var exportDir = ""
  var overwrite = true
  var runGenerate = false
  var writeQueryStubs = true

  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption:
      case p.key
      of "export":
        action = raExport
        exportDir = p.val
        if exportDir.len == 0:
          p.next()
          if p.kind == cmdArgument:
            exportDir = p.key
          else:
            stderr.writeLine "Error: --export requires a directory argument"
            quit(1)
      of "summary":
        action = raSummary
      of "validate":
        action = raValidate
      of "overwrite":
        overwrite = true
      of "no-overwrite":
        overwrite = false
      of "run-generate":
        runGenerate = true
      of "no-query-stubs":
        writeQueryStubs = false
      else:
        stderr.writeLine "Unknown option: --" & p.key
        quit(1)
    of cmdShortOption:
      stderr.writeLine "Unknown option: -" & p.key
      quit(1)
    of cmdArgument:
      if action == raPrintJs:
        action = raExport
        exportDir = p.key

  case action
  of raPrintJs:
    echo g.renderGrammarJs()
  of raSummary:
    echo g.summary()
  of raValidate:
    echo "Grammar \"" & g.name & "\" is valid."
  of raExport:
    if exportDir.len == 0:
      stderr.writeLine "Error: --export requires a directory argument"
      quit(1)
    let config = mkExportConfig(
      outDir = exportDir,
      runGenerate = runGenerate,
      writeQueryStubs = writeQueryStubs,
      overwrite = overwrite,
    )
    g.exportGrammar(config)
    echo "Exported grammar \"" & g.name & "\" to " & exportDir
