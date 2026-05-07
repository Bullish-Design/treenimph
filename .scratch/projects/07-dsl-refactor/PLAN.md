# PLAN

## Absolute Rule Reminder
NEVER use subagents (Task tool). All work is performed directly in this session.

## Objective
Implement `.scratch/projects/06-final-roadmap/DSL_IMPLEMENTATION_GUIDE.md` end-to-end, including runner integration, new DSL macro module, tests, example rewrites, and final validation.

## Steps
1. Create runner module and validate compile.
2. Wire runner into root module and run tests.
3. Update examples to use `run()` and verify behavior.
4. Add runner tests and pass test suite.
5. Add DSL scaffold + `transformExpr` and validate.
6. Add DSL `grammar` macro and run smoke check.
7. Add DSL unit tests (`test_dsl.nim`) and pass.
8. Add DSL integration tests and pass.
9. Add DSL equivalence tests and pass.
10. Rewrite examples to DSL while preserving raw copies.
11. Add DSL error-handling tests and pass.
12. Run full validation gate and cleanup.

## Acceptance Criteria
- All implementation-guide steps completed with passing checks.
- Quality gate satisfied:
  - `devenv shell -- nim check` on edited Nim modules.
  - relevant Nim test/entrypoint runs pass.
  - export-affecting changes validated with `devenv shell -- tree-sitter generate`.
- Commit and push after each step.

## Absolute Rule Reminder
NEVER use subagents (Task tool). All work is performed directly in this session.
