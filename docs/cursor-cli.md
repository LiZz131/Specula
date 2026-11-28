# Cursor CLI

Select Cursor CLI with `--agent=cursor-cli`, or with `"agent": "cursor-cli"` in a profile of a [hybrid agent configuration](Usage.md#hybrid-agent-configuration). Specular runs the Cursor CLI executable `cursor-agent`. It has been tested with Cursor CLI 2026.11.22-e9042b2 on Linux with the `grok-4.7-low` model; older builds still run but print a warning.

## Install and authenticate

Install the CLI with `curl https://cursor.com/install -fsS | bash`, then authenticate once with `cursor-agent login`, or set `CURSOR_API_KEY`. `specular setup` then installs Specular's skills and MCP servers for Cursor; see [Skills and MCP servers](#skills-and-mcp-servers).

## Models and reasoning effort

Cursor CLI has no reasoning-effort option. The effort is part of the model name, so choose a model name that includes it. `cursor-agent models` lists the names, for example `grok-4.7-low` and `grok-4.7-high`. Names do not follow one pattern: some put the effort at the end, some in the middle (`claude-opus-5-thinking-high`), and some have no effort levels.

Set the model with `--model`, with `CURSOR_MODEL`, or with a profile's `model`:

```json
"profiles": {
  "cursor": {"agent": "cursor-cli", "model": "grok-4.7-low"}
}
```

`--effort`, `CURSOR_EFFORT`, and a profile's `effort` are accepted, but Cursor does not use them: each agent launch prints a warning that the effort is ignored. `run.json` still records the requested effort. Avoid the `-fast` model variants unless you want Cursor's faster, higher-priced models.

## How Specular runs Cursor

Specular runs `cursor-agent -p --output-format stream-json --stream-partial-output --trust --force` in the step's working directory, so the agent edits files and runs shell commands without prompting. Without `--force`, Cursor rejects shell commands silently. The prompt is passed on standard input, so its size is not limited by the command line.

Cursor has no system-prompt option and reads rule files only from the workspace, so Specular places its rules at the start of the prompt instead of writing files into your repository. Skills are referenced by their file paths under the Specular checkout.

Each run's readable log, raw event stream (`.activity.jsonl`), and token usage (`.usage.json`) are recorded. Cursor reports no cost, so the resource summary marks Cursor cost as incomplete.

Specular resumes the exact Cursor chat recorded for a turn with `--resume`. Cursor does not reject an unknown chat ID: it silently starts an empty chat under that ID. Before resuming, Specular therefore checks that Cursor still stores the chat (under `$CURSOR_CONFIG_DIR/chats` or `~/.cursor/chats`), and refuses to resume one that has been removed. Cursor keeps chats and other per-directory state under `~/.cursor` for every working directory it runs in, including the temporary directories used for bug confirmation; Specular does not remove them.

## Skills and MCP servers

`specular setup` installs the skills into `~/.cursor/skills` and registers Specular's three MCP servers in `~/.cursor/mcp.json`. It never overwrites an existing entry with the same name; it prints the entry to add by hand instead. Pipeline runs do not depend on the installed skills, but interactive use does. The Cursor editor reads the same `~/.cursor/mcp.json`, so the servers also appear there.

Cursor also loads skills from `~/.claude/skills`, `~/.codex/skills`, and `~/.agents/skills`. A skill in `~/.cursor/skills` takes precedence over one with the same name there, so rerun `specular setup` after moving or updating the checkout to keep the agent from reading another checkout's copy.

Cursor has no option that adds an MCP server for a single run, so for each run Specular adds its TLC task tool, and in single-session and incremental runs its context tools, to the working directory's `.cursor/mcp.json`. It keeps any servers already in the file and the file's permissions, and restores the file afterwards. Cursor loads a server from that file only after approval. Specular approves only its own servers (`cursor-agent mcp enable`), so servers that the analyzed repository defines in its own `.cursor/mcp.json` are not started unless you approved them before. A `.cursor/mcp.json` that is a symbolic link is left unchanged, and the agent then uses the equivalent shell scripts.

Cursor ends every MCP tool call after 60 seconds. Each TLC wait therefore returns before that limit and the agent waits again. Other MCP calls that run longer than 60 seconds fail, and the agent falls back to the equivalent shell scripts.

## Account and team rules

Cursor applies the User Rules of your Cursor account (Cursor Settings → Rules) and any Team Rules set by your team's administrators to every Specular run, including headless ones. They are stored with the account rather than on this machine, so they apply on every machine where you are logged in, and Specular cannot turn them off. A rule meant for interactive use can change Specular's results: for example, a rule asking for replies in another language makes agents write confirmation reports in that language. Review these rules before starting a run and remove ones that conflict with Specular's workflow.

## Single-session and incremental runs

With `--orchestration=single-session` and `--incremental`, Cursor CLI has no command that compacts a conversation from a script. When the controller requests compaction, Specular continues the same chat without compacting it, as with Antigravity CLI; Cursor summarizes the conversation itself when the context window fills.

## Limitations

- The optional agent sandbox (`SPECULAR_SANDBOX=on`) is not available for Cursor CLI.
- Cursor does not provide Specular's agent-side stop gate.
- `--max-turns` is accepted but not enforced.
