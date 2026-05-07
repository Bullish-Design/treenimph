# CONTEXT

Completed Step 2 from `DSL_IMPLEMENTATION_GUIDE.md`.

- Updated `src/treenimph.nim` to import/export `treenimph/runner`.
- Verified with:
  - `devenv shell -- nim check -p:src src/treenimph.nim`
  - `devenv shell -- nimble test`
- Next action: Step 3 update examples to call `run(grammar)`.
