# PLAN

## Scope
Implement `.scratch/projects/02-mvp-concept/MVP_IMPLEMENTATION_GUIDE.md` end-to-end.

## Steps
1. Project bootstrap
- Create Nim package structure (`src`, `tests`, `examples`) and `treenimph.nimble`.
- Add baseline modules and test runner task.

2. Core modules
- Implement model, diagnostics, validation, JS/package rendering, helpers, exporter, top-level API.

3. Tests
- Implement module tests and integration/example tests, including snapshots.

4. Verification
- Run `nimble build` and `nimble test`, fix failures.

5. Commit/push policy
- Commit and push after each completed phase from the implementation guide.

## Acceptance Criteria
- All guide deliverables implemented.
- `nimble build` succeeds.
- `nimble test` passes.
- Examples compile and run.
