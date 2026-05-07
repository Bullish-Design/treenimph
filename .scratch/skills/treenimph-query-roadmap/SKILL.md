# TreeNimph Query Roadmap

Use this skill when designing or implementing future TreeNimph query support.

## Current Product Stage
- v1 focus is grammar DSL and package export.
- Query authoring is planned, not required for initial delivery.

## Query Separation Model
Keep query concerns as separate files under exported package `queries/`:
- `highlights.scm`
- `locals.scm`
- `injections.scm`
- `tags.scm`

## Implementation Guidance
- Treat query support as an additive module, not mixed into core grammar types.
- Keep grammar export stable before layering query export features.
- Prefer a file-per-domain architecture aligned with Tree-sitter conventions.

## Acceptance Criteria For Query Work
- Generated files map cleanly to Tree-sitter naming conventions.
- Captures and patterns remain transparent, with no opaque abstraction layer.
- Query features do not regress grammar-only workflows.
