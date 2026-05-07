# DECISIONS

1. Constructor naming collision with Nim symbols
- Decision: use `mkRule`, `mkGrammar`, `mkExportConfig` for constructor helpers.
- Reason: Nim does not allow proc names that collide with type names in this layout.

2. Grammar constructor signature
- Decision: use `rules: openArray[Rule]` rather than `varargs[Rule]`.
- Reason: Nim varargs with trailing optional params produced call-site ambiguity; openArray is stable and explicit.
