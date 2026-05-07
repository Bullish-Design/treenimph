# CONTEXT

MVP implementation guide has been executed end-to-end.

Implemented modules:
- `model.nim`
- `diagnostics.nim`
- `validate.nim`
- `render_js.nim`
- `render_package.nim`
- `helpers.nim`
- `exporter.nim`
- `src/treenimph.nim` (public API)

Implemented tests:
- `test_model.nim`
- `test_diagnostics.nim`
- `test_validate.nim`
- `test_render_js.nim` + snapshot
- `test_render_package.nim`
- `test_helpers.nim`
- `test_export.nim`
- `test_examples.nim`

Implemented examples:
- `examples/arithmetic.nim`
- `examples/json_like.nim`
- `examples/simple_lang.nim`

Verification status:
- `devenv shell -- nimble test` passes.

Notable deviations documented in `DECISIONS.md`:
- Constructor helper names are `mkRule`, `mkGrammar`, `mkExportConfig`.
- `mkGrammar` uses `rules: openArray[Rule]` and `rules = [...]` call style.
