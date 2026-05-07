# Context

Completed Step 2 in `src/treenimph/exporter.nim`:
- `isTreeNimphPackageJson`: `except CatchableError`
- `isTreeNimphTreeSitterJson`: `except CatchableError`

Verification run:
- `devenv shell -- nim check -p:src src/treenimph/exporter.nim` passed
- `devenv shell -- nim r -p:src tests/test_export.nim` passed
- bare `except:` check returned no matches

Next: Step 3, add nil guard/import in `render_js` and add nil-body test in `tests/test_render_js.nim`.
