# Context

Implemented Step 1 from the refactor guide: removed `bin = @["treenimph"]` from `treenimph.nimble`.

Verification run:
- `devenv shell -- nim r -p:src tests/test_model.nim` passed
- `devenv shell -- nim r -p:src tests/test_export.nim` passed

Next: Step 2 (`src/treenimph/exporter.nim`) replace bare `except:` with `except CatchableError:`, verify with `nim check` and exporter tests, then commit/push.
