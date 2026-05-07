import std/[os, strutils]
import unittest

const updateFixturesEnv* = "TREENIMPH_UPDATE_FIXTURES"

proc normalizeNewlines*(s: string): string =
  s.replace("\r\n", "\n")

proc fixturePath*(parts: varargs[string]): string =
  result = "tests"
  for p in parts:
    result = result / p

proc readFixture*(path: string): string =
  readFile(path).normalizeNewlines()

proc writeFixture*(path: string, content: string) =
  createDir(path.parentDir())
  writeFile(path, content.normalizeNewlines())

proc assertMatchesFixture*(actual: string, expectedPath: string) =
  let normalizedActual = actual.normalizeNewlines()
  if existsEnv(updateFixturesEnv):
    writeFixture(expectedPath, normalizedActual)
    checkpoint("Updated fixture: " & expectedPath)
    return

  check fileExists(expectedPath)
  let expected = readFixture(expectedPath)
  if normalizedActual != expected:
    let previewLimit = 600
    let expectedPreview = if expected.len > previewLimit: expected[0 ..< previewLimit] & "\n..." else: expected
    let actualPreview = if normalizedActual.len > previewLimit: normalizedActual[0 ..< previewLimit] & "\n..." else: normalizedActual
    checkpoint("Fixture mismatch at " & expectedPath)
    checkpoint("Expected preview:\n" & expectedPreview)
    checkpoint("Actual preview:\n" & actualPreview)
  check normalizedActual == expected
