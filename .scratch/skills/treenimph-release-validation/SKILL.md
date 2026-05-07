# TreeNimph Export Validation

Use this skill before finalizing changes that affect generated grammar package output.

## Goal
Ensure TreeNimph emits a package structure that tools can consume like any hand-written Tree-sitter grammar package.

## Validation Checklist
1. Export a package to a clean output directory.
2. Confirm required files exist (at minimum `grammar.js`; include package metadata used by project).
3. Run `tree-sitter generate` in exported package when available.
4. Confirm generated artifacts are created successfully and no schema/runtime errors are emitted.

## Canonical Commands
- Export via project script or Nim entrypoint.
- Validate with: `devenv shell -- tree-sitter generate`

## Failure Handling
- Treat generation failures as blockers.
- Prefer fixing model/render output over adding compatibility shims.
