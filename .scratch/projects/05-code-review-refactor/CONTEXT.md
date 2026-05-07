# Context

Completed Step 3:
- Added nil-body assertions at start of `renderGrammarJs`.
- Added `raises on nil rule body` test in `tests/test_render_js.nim`.

Verification run:
- `devenv shell -- nim check -p:src src/treenimph/render_js.nim` passed
- `devenv shell -- nim r -p:src tests/test_render_js.nim` passed (4 tests)
- `devenv shell -- nim r -p:src tests/test_export.nim` passed
- `devenv shell -- nim r -p:src tests/test_examples.nim` passed

Next: Step 4 (expand JS escaping + export helper procs + add escape-focused tests).
