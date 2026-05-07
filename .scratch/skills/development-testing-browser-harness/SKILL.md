# Development Testing With Browser Harness

Use this skill whenever running Browsee demos or real-world browser runs (for example `browsee explore`, `scripts/demo_trace_capture.sh`, or any script relying on `browser-harness`).

## Goal

Prevent runtime failures caused by missing Chrome DevTools remote debugging (for example `DevToolsActivePort not found`).

## Required Workflow

1. Always run the Chrome debug bootstrap first:
   - `devenv shell -- bash scripts/ensure_chrome_debug.sh`
2. Export the values printed by the script in the current shell:
   - `export BU_CDP_WS='ws://127.0.0.1:<port>/devtools/browser/<id>'`
   - `export BROWSEE_CHROME_DEBUG_PORT='<port>'`
3. Run the demo or real-world test command using `devenv shell -- ...`.

## Shortcut

`devenv shell -- bash scripts/demo_trace_capture.sh` now bootstraps Chrome debug automatically by invoking `scripts/ensure_chrome_debug.sh` and exporting `BU_CDP_WS` before it runs explores.

## Validation

Before starting runs, confirm:
- `BU_CDP_WS` is set (`echo "$BU_CDP_WS"`), and
- `curl -fsS "http://127.0.0.1:${BROWSEE_CHROME_DEBUG_PORT:-9333}/json/version"` returns JSON.

If bootstrap fails, inspect `/tmp/browsee_chrome_debug.log`.
