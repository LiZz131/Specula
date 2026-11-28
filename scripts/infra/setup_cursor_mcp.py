#!/usr/bin/env python3
"""Register Specular MCP servers in Cursor CLI's user configuration.

Cursor CLI has no `mcp add` command; it reads servers from ~/.cursor/mcp.json
(and a workspace's .cursor/mcp.json). This helper adds one stdio server entry
without disturbing anything else in the file:

  * an identical existing entry is left alone ("already configured");
  * a different entry under the same name, an unreadable/invalid file, or a
    symbolic link is never rewritten (the user resolves it);
  * otherwise the entry is added and the file replaced atomically.

Usage: setup_cursor_mcp.py CONFIG_FILE NAME PROJECT_ROOT PYTHON SERVER
Exit status: 0 configured or already configured, 3 left unchanged, 2 usage.
"""

from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

UNCHANGED = 3


def entry(project_root: str, python: str, server: str) -> dict[str, object]:
    return {"command": python, "args": [server], "env": {"SPECULAR_ROOT": project_root}}


def register(config: Path, name: str, wanted: dict[str, object]) -> tuple[int, str]:
    if config.is_symlink():
        return UNCHANGED, f"{config} is a symbolic link; add the '{name}' server manually"
    payload: object = {}
    if config.exists():
        try:
            payload = json.loads(config.read_text(encoding="utf-8"))
        except (OSError, UnicodeError, ValueError) as exc:
            return UNCHANGED, f"{config} could not be read as JSON ({exc}); it was left unchanged"
    if not isinstance(payload, dict) or not isinstance(payload.get("mcpServers", {}), dict):
        return UNCHANGED, f"{config} does not hold an mcpServers object; it was left unchanged"
    servers = payload.setdefault("mcpServers", {})
    if name in servers:
        if servers[name] == wanted:
            return 0, f"Cursor MCP already configured: {name}"
        return UNCHANGED, f"Cursor MCP '{name}' in {config} differs from Specular's and was left unchanged"
    servers[name] = wanted
    config.parent.mkdir(parents=True, exist_ok=True)
    fd, raw = tempfile.mkstemp(prefix=f".{config.name}.", dir=config.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            json.dump(payload, stream, indent=2)
            stream.write("\n")
        if config.exists():
            os.chmod(raw, config.stat().st_mode & 0o777)
        os.replace(raw, config)
    except BaseException:
        Path(raw).unlink(missing_ok=True)
        raise
    return 0, f"Cursor MCP configured: {name}"


def main(argv: list[str]) -> int:
    if len(argv) != 5:
        print(__doc__, file=sys.stderr)
        return 2
    config, name, project_root, python, server = argv
    wanted = entry(project_root, python, server)
    status, message = register(Path(config), name, wanted)
    print(message)
    if status == UNCHANGED:
        # Like the other agents' setup, show what to add by hand.
        print(f'  Add under "mcpServers" in {config}: {json.dumps({name: wanted})[1:-1]}')
    return status


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
