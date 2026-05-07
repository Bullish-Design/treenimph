# AGENTS.md

Read `.scratch/CRITICAL_RULES.md` first in every session.
If `.scratch/REPO_RULES.md` conflicts with TreeNimph Nim/Tree-sitter workflows, follow this file.

Operational reminders:
- Never use subagents.
- Keep project tracking files in `.scratch/projects/<num>-<name>/` up to date.
- Use `devenv shell -- ...` for all environment-dependent CLI commands.
- This includes Nim checks/runs, export validation, and Tree-sitter generation.

TreeNimph development commands:
- Nim compile check: `devenv shell -- nim check <file>.nim`
- Nim run: `devenv shell -- nim r <file>.nim`
- Tree-sitter CLI version: `devenv shell -- tree-sitter --version`
- Validate exported package: `devenv shell -- tree-sitter generate`

Available local skills:
- `.scratch/skills/treenimph-grammar-dsl/SKILL.md`
- `.scratch/skills/treenimph-query-roadmap/SKILL.md`
- `.scratch/skills/treenimph-release-validation/SKILL.md`

Quality gate checklist before finalizing TreeNimph changes:
1. Run `devenv shell -- nim check` on edited Nim modules.
2. Run the relevant Nim entrypoint/tests for changed behavior.
3. For export-affecting changes, generate an output package and run `devenv shell -- tree-sitter generate` in that package.
4. If checks fail, fix and rerun until clean; mention unresolved blockers explicitly.
