# CONTEXT

Completed Step 1 from `DSL_IMPLEMENTATION_GUIDE.md`.

- Added `src/treenimph/runner.nim` with `run*(g: Grammar)` CLI dispatch.
- Verified with: `devenv shell -- nim check -p:src src/treenimph/runner.nim`.
- Next action: Step 2 wire `runner` into `src/treenimph.nim`, validate, then run tests.
