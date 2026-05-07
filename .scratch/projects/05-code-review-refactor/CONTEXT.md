# Context

Completed Step 4:
- `escapeJsSingleQuote` now exported and escapes null/control chars (`\\0`, `\\xNN`).
- `escapeRegexSlash` now exported.
- Added `escapeJsSingleQuote` and `escapeRegexSlash` test suites to `tests/test_render_js.nim`.

Verification run:
- `devenv shell -- nim check -p:src src/treenimph/render_js.nim` passed
- `devenv shell -- nim r -p:src tests/test_render_js.nim` passed (16 tests total at this point)

Next: Step 5 (escape grammar name in `renderGrammarJs`), then run render/export/examples checks.
