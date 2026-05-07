# CONTEXT

Completed Phase 1 (`model.nim`) with constructors, accessors, canonical naming, and summary.
`tests/test_model.nim` now covers model construction and behavior; test run passes.

Notable API deviations from guide due Nim constraints:
- `mkRule`, `mkGrammar`, `mkExportConfig` helper names
- `mkGrammar` uses `openArray[Rule]` and call style `rules = [...]`

Next: implement Phase 2 diagnostics and its tests.
