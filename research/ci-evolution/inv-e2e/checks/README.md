# Checks used while running epoch 2

Operational helpers, kept here so every check that informed a decision is in git.

| Script | Use |
|---|---|
| `watchdog.sh` | One monitoring tick (default: sleep 1800 s): round log tail, newest session's API/tool/MCP counts, MCP errors, `specular`/old-name commands, bwrap and TLC process counts, host OAuth hours left. Also the 5-hour/7-day quota of each saved account (`ca usage`). `W=<WORK> LOG=<round log> [SLEEP=0] checks/watchdog.sh` |
| `tool_errors.py [GLOB]` | MCP calls and error results per session log (default: all epoch-2 sessions). |
| `verify_specular_cli.py WS MAIN_TOOLS` | In the agent's sandbox: environment, `specular --help`, `specular findings lookup`, a synthetic `final-result.json` through `specular ci-result`. Writes into WS: use a throwaway workspace. |
| `verify_findings_lookup.py WS MAIN_TOOLS` | `specular findings lookup`/`check` after the previous script recorded a finding. |
| `verify_start_background.py WS MAIN_TOOLS` | `start_background.sh` → `run_model_check.sh` → `wait_for_pid.sh` on a small liveness spec (needs `current/tmp-tlc/` with `Lasso.tla` and `stuttering.cfg`, and `.stop-gate`, `.tlc-tasks` in WS). |
| `verify_rust.py WS MAIN_TOOLS` | Rust toolchains (pinned nightly and the prior harness's default) inside the sandbox. |
| `verify_init_sandbox.py` | Read/write layout and `specular` in a `prepare_init.py` workspace (needs the I-9 init tools). |

All of them build the sandbox with `agent.bwrap_command`, never start an agent session, and cost nothing.
