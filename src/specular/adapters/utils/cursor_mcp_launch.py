"""Start one of a run's Specular MCP servers under Cursor CLI.

Cursor starts MCP servers with a minimal environment (HOME, PATH, USER, ...),
not the agent's, so a server would lose the run's working directory, TLC owner,
and context-control request. The workspace ``.cursor/mcp.json`` entry is the
same for every run (concurrent runs share that file), so it passes the per-run
launch description in one variable, ``SPECULAR_CURSOR_MCP``: base64-encoded
JSON ``{"server": PATH, "env": {NAME: VALUE}}``. This launcher, run by the
server's own Python, applies that environment and replaces itself with the
server. Standard library only.
"""

from __future__ import annotations

import base64
import binascii
import json
import os
import sys

VARIABLE = "SPECULAR_CURSOR_MCP"


def decode(raw: str) -> tuple[str, dict[str, str]]:
    """Return the server path and environment of a launch description."""
    try:
        spec = json.loads(base64.b64decode(raw.encode("ascii"), validate=True))
    except (UnicodeError, binascii.Error, ValueError) as exc:
        raise ValueError(f"{VARIABLE} is not a base64-encoded JSON launch description") from exc
    server = spec.get("server") if isinstance(spec, dict) else None
    env = spec.get("env") if isinstance(spec, dict) else None
    if not isinstance(server, str) or not server:
        raise ValueError(f"{VARIABLE} names no server")
    if not isinstance(env, dict) or not all(isinstance(k, str) and isinstance(v, str) for k, v in env.items()):
        raise ValueError(f"{VARIABLE} has an invalid environment")
    return server, env


def main() -> int:
    raw = os.environ.pop(VARIABLE, "")
    try:
        server, extra = decode(raw)
    except ValueError as exc:
        print(f"specular cursor MCP launcher: {exc}", file=sys.stderr)
        return 2
    os.execve(sys.executable, [sys.executable, server], {**os.environ, **extra})
    return 1  # not reached


if __name__ == "__main__":
    raise SystemExit(main())
