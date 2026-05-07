# TreeNimph Grammar DSL Workflow

Use this skill when implementing or refactoring TreeNimph's Nim object model for Tree-sitter grammar authoring.

## Scope
- Grammar-domain model types (`Grammar`, `Rule`, `Expr`, and concrete expression types).
- Validation before export.
- Rendering/export pipeline to standard Tree-sitter package structure.

## Design Constraints
- Keep one public authoring style: explicit, typed, composable Nim objects.
- Do not introduce JS-style DSL shortcuts like `$.name` in the public API.
- Preserve strict compatibility at the output boundary (`grammar.js` and package layout).

## Canonical Iteration Loop
1. Implement model or renderer changes in Nim.
2. Generate/export a sample grammar package.
3. Validate generated `grammar.js` is deterministic and readable.
4. If `tree-sitter` CLI is available, run generation against exported package.

## Useful Commands
- Nim compile check: `devenv shell -- nim check <file>.nim`
- Nim run: `devenv shell -- nim r <file>.nim`
- Tree-sitter package generation: `devenv shell -- tree-sitter generate`

## Validation Expectations
- Missing references and invalid rule graphs should fail with explicit errors.
- Export should not require downstream tools to know TreeNimph exists.
