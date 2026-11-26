"""Adapter: cursor-cli (Cursor CLI, ``cursor-agent``).

Options:
  --prompt=...          Task prompt (mutually exclusive with --prompt-file)
  --prompt-file=FILE    Read prompt from file (mutually exclusive with --prompt)
  --max-turns=N         Accepted for launcher compatibility; ignored
  --claude-alias=NAME   Accepted for launcher compatibility; ignored
  --effort=LEVEL        Accepted; ignored with a warning. Cursor has no effort
                        option: choose the effort in the model slug instead
                        (default: CURSOR_EFFORT)
  --model=NAME          Cursor model slug, e.g. grok-4.7-low; list them with
                        `cursor-agent models` (default: CURSOR_MODEL)
  --log=FILE            Log file path (required)
  --resume-state=PATH   Persist/resume the exact native Cursor chat
  --system-prompt-file=FILE
                        Prepend FILE to the prompt if not already included
  --background          Accepted; caller handles backgrounding
  --help                Show this help

Authenticate first with `cursor-agent login` or set CURSOR_API_KEY.
"""

from __future__ import annotations

import contextlib
import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections.abc import Iterator
from dataclasses import replace
from pathlib import Path

if __package__:
    from .utils.json_cli import AdapterArgumentError, AdapterOptions, parse_options, run_json_cli
    from .utils.resume import ResumeStateError, read_session_id
else:
    from utils.json_cli import (  # type: ignore[import-not-found, no-redef]
        AdapterArgumentError,
        AdapterOptions,
        parse_options,
        run_json_cli,
    )
    from utils.resume import ResumeStateError, read_session_id  # type: ignore[import-not-found, no-redef]

HELP = __doc__
SPECULAR_ROOT = Path(__file__).resolve().parents[3]
# Oldest Cursor CLI build this adapter has been tested with. Older builds are
# still attempted; the adapter only warns.
MIN_TESTED_VERSION = "2026.11.22"
INSTALL_HINT = "install Cursor CLI with `curl https://cursor.com/install -fsS | bash`, then run `cursor-agent login`"
_VERSION_RE = re.compile(r"^(\d{4})\.(\d{1,2})\.(\d{1,2})\b")


def _executable() -> str:
    """Cursor installs the same binary as ``cursor-agent`` and the generic ``agent``."""
    return shutil.which("cursor-agent") or shutil.which("agent") or "cursor-agent"


def _warn_if_untested_version(executable: str) -> None:
    try:
        result = subprocess.run([executable, "--version"], capture_output=True, text=True, timeout=15, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return  # a missing/hung CLI is reported by the real launch
    match = _VERSION_RE.match(result.stdout.strip())
    minimum = _VERSION_RE.match(MIN_TESTED_VERSION)
    if match is None or minimum is None:
        return
    if tuple(map(int, match.groups())) < tuple(map(int, minimum.groups())):
        print(
            f"cursor-cli adapter: Cursor CLI {result.stdout.strip()} is older than the oldest tested version "
            f"{MIN_TESTED_VERSION}; continuing",
            file=sys.stderr,
        )


def _chats_root(env: dict[str, str]) -> Path:
    """Where Cursor keeps chats: ``<config dir>/chats/<md5 of workspace>/<chat id>/``."""
    configured = env.get("CURSOR_CONFIG_DIR", "").strip()
    if configured:
        return Path(configured).expanduser() / "chats"
    xdg = env.get("XDG_CONFIG_HOME", "").strip()
    if xdg and (Path(xdg) / "cursor" / "chats").is_dir():
        return Path(xdg) / "cursor" / "chats"
    return Path(env.get("HOME") or Path.home()) / ".cursor" / "chats"


def _chat_exists(env: dict[str, str], session_id: str) -> bool | None:
    """Whether Cursor still stores chat ``session_id``; None when that cannot be told.

    Cursor does not reject ``--resume`` of an unknown ID: it silently starts a
    new chat under that ID. Resuming must therefore verify the chat first, or a
    lost or cleaned-up chat would continue with no history while looking resumed.
    """
    root = _chats_root(env)
    if not root.is_dir():
        return None  # unknown storage layout: do not block resume on a guess
    try:
        return any((workspace / session_id / "meta.json").is_file() for workspace in root.iterdir())
    except OSError:
        return None


def _extra_workspace_dirs(env: dict[str, str], cwd: Path) -> list[str]:
    """Return existing Specular/target directories outside cwd for --add-dir."""
    candidates = [
        env.get("SPECULAR_ROOT") or str(SPECULAR_ROOT),
        env.get("SPECULAR_TARGET_REPO_DIR", ""),
        env.get("SPECULAR_WORK_DIR", ""),
    ]
    resolved_cwd = cwd.resolve()
    dirs: list[str] = []
    seen: set[Path] = {resolved_cwd}
    for candidate in candidates:
        if not candidate:
            continue
        try:
            path = Path(candidate).expanduser().resolve()
        except OSError:
            continue
        if path.is_dir() and path not in seen:
            dirs.append(str(path))
            seen.add(path)
    return dirs


def _stage_prompt(options: AdapterOptions) -> AdapterOptions:
    """Prepend the pinned rules to the stdin prompt unless the prompt already holds them.

    Cursor has no system-prompt option, and it reads rule files (AGENTS.md,
    .cursor/rules) only from the workspace, which Specular must not modify.
    """
    if options.system_prompt_file is None:
        return options
    system_text = options.system_prompt_file.read_text(encoding="utf-8", errors="replace").strip()
    prompt_text = options.prompt_path.read_text(encoding="utf-8", errors="replace")
    if not system_text or system_text in prompt_text:
        return options
    fd, raw_path = tempfile.mkstemp(prefix="specular-cursor-cli-stdin-", suffix=".txt", text=True)
    staged = Path(raw_path)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(f"{system_text}\n\n---\n\n{prompt_text}")
    except BaseException:
        staged.unlink(missing_ok=True)
        raise
    return replace(options, prompt_path=staged, temporary_prompt=True)


# Cursor reads MCP servers only from <workspace>/.cursor/mcp.json and
# ~/.cursor/mcp.json (neither --add-dir nor CURSOR_CONFIG_DIR is consulted), and
# it expands ${env:NAME} in them. Specular never edits the user's global agent
# settings, so its per-run servers are registered in the workspace file. Each
# server's entry is constant: the per-run values travel in the agent's
# environment, which Cursor passes on to the MCP server. Concurrent runs in one
# workspace therefore agree on every entry; the file holds the union of the
# servers the live runs need, and the original returns when the last one exits.
TLC_WAIT_LIMIT_SECONDS = 45
_MCP_STATE = ".specular-mcp"
# server name -> (Specular's per-run MCP JSON variable, python variable, server-path variable)
_MCP_SERVERS = {
    "specular_tlc": ("SPECULAR_TLC_TOOL_JSON", "SPECULAR_TLC_TOOL_PYTHON", "SPECULAR_TLC_TOOL_SERVER"),
    "specular_context": ("SPECULAR_CONTEXT_MCP_JSON", "SPECULAR_CONTEXT_PYTHON", "SPECULAR_CONTEXT_SERVER"),
}
# Context-control phases (specular.context_control.CONTEXT_CONTROL_PHASES) get the context tools.
_CONTEXT_PHASES = {"incremental", "main"}


def _mcp_entry(server: str) -> dict[str, object]:
    _, python, path = _MCP_SERVERS[server]
    return {"command": f"${{env:{python}}}", "args": [f"${{env:{path}}}"]}


def _run_servers(env: dict[str, str]) -> list[str]:
    """Export the launch values of the Specular MCP servers this run gets; return their names."""
    servers: list[str] = []
    for server, (source, python, path) in _MCP_SERVERS.items():
        if server == "specular_context" and env.get("SPECULAR_PHASE") not in _CONTEXT_PHASES:
            continue
        try:
            entry = json.loads(env.get(source) or "null")["mcpServers"][server]
            command, args = entry["command"], entry["args"]
        except (ValueError, KeyError, TypeError):
            continue
        if isinstance(command, str) and isinstance(args, list) and len(args) == 1 and isinstance(args[0], str):
            env[python], env[path] = command, args[0]
            servers.append(server)
    if "specular_tlc" in servers:
        # Cursor ends every MCP tool call after a fixed 60 s; keep each wait_tlc below it.
        env["SPECULAR_TLC_TOOL_WAIT_LIMIT"] = str(TLC_WAIT_LIMIT_SECONDS)
    return servers


def _pid_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _live_servers(state: Path) -> set[str] | None:
    """Servers needed by live runs (each marker lists its own); None when no run is live."""
    live: set[str] | None = None
    for marker in state.glob("run-*"):
        try:
            pid = int(marker.name.split("-")[1])
        except (IndexError, ValueError):
            continue
        if not _pid_alive(pid):
            marker.unlink(missing_ok=True)
            continue
        try:
            names = marker.read_text().split()
        except OSError:
            names = []
        live = (live or set()) | {name for name in names if name in _MCP_SERVERS}
    return live


def _replace_file(path: Path, data: bytes) -> None:
    fd, raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
        os.replace(raw, path)
    except BaseException:
        Path(raw).unlink(missing_ok=True)
        raise


def _merged_config(saved: bytes, servers: set[str]) -> bytes:
    """The user's workspace MCP config (from the backup) plus the Specular servers."""
    try:
        base = json.loads(saved[1:].decode()) if saved[:1] == b"1" else {}
    except ValueError:
        base = {}
    base = dict(base) if isinstance(base, dict) else {}
    existing = base.get("mcpServers")
    base["mcpServers"] = {
        **(existing if isinstance(existing, dict) else {}),
        **{server: _mcp_entry(server) for server in sorted(servers)},
    }
    return (json.dumps(base, indent=2) + "\n").encode()


@contextlib.contextmanager
def _state_lock(state: Path) -> Iterator[None]:
    """Hold the workspace's lock; retry if the last run removed it meanwhile."""
    while True:
        state.mkdir(parents=True, exist_ok=True)
        path = state / "lock"
        with path.open("a+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                current = os.stat(path)
            except FileNotFoundError:
                continue
            if os.fstat(lock.fileno()).st_ino != current.st_ino:
                continue
            yield
            return


@contextlib.contextmanager
def _workspace_mcp(cwd: Path, env: dict[str, str]) -> Iterator[list[str]]:
    """Expose this run's Specular MCP servers to Cursor; yield their names."""
    servers = _run_servers(env)
    if not servers:
        yield servers
        return
    directory = cwd / ".cursor"
    config_path = directory / "mcp.json"
    state = directory / _MCP_STATE
    backup = state / "original"
    marker = state / f"run-{os.getpid()}-{os.urandom(4).hex()}"
    directory_existed = directory.is_dir()
    with _state_lock(state):
        live = _live_servers(state)
        # A leftover backup means an earlier run died while holding the file.
        if live is None and not backup.exists():
            original = config_path.read_bytes() if config_path.is_file() else None
            backup.write_bytes(b"0" if original is None else b"1" + original)
            if not directory_existed:
                (state / "created-directory").touch()
        needed = (live or set()) | set(servers)
        if needed != live:
            _replace_file(config_path, _merged_config(backup.read_bytes(), needed))
        marker.write_text("\n".join(servers) + "\n")
    try:
        yield servers
    finally:
        with _state_lock(state):
            marker.unlink(missing_ok=True)
            live = _live_servers(state)
            if live is not None:
                _replace_file(config_path, _merged_config(backup.read_bytes(), live))
            else:
                saved = backup.read_bytes() if backup.exists() else b"0"
                if saved[:1] == b"1":
                    _replace_file(config_path, saved[1:])
                else:
                    config_path.unlink(missing_ok=True)
                remove_directory = (state / "created-directory").exists()
                shutil.rmtree(state, ignore_errors=True)
                if remove_directory:
                    with contextlib.suppress(OSError):
                        directory.rmdir()


# The CLI's own failure lines (stderr, merged into the event stream). Only used
# after the CLI failed, so the readable log holds its diagnostics.
_FAILURE_HINTS = (
    (
        re.compile(r"authentication required|api key is invalid|not authenticated|not logged in", re.IGNORECASE),
        "authenticate with `cursor-agent login` or set CURSOR_API_KEY",
    ),
    (re.compile(r"cannot use this model", re.IGNORECASE), "list the available model slugs with `cursor-agent models`"),
)


def _report_failure(log_path: Path) -> None:
    """Repeat the CLI's final diagnostic on stderr with an actionable hint."""
    try:
        lines = log_path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return
    for line in reversed(lines):
        hint = next((hint for pattern, hint in _FAILURE_HINTS if pattern.search(line)), None)
        if hint is not None:
            diagnostic = line.removeprefix("adapter error: ")
            break
    else:
        errors = [line for line in lines if line.startswith("adapter error: ")]
        if not errors:
            return
        diagnostic, hint = errors[-1].removeprefix("adapter error: "), None
    shown = diagnostic if len(diagnostic) <= 300 else diagnostic[:297] + "..."
    print(f"cursor-cli adapter: {shown}" + (f" ({hint})" if hint else ""), file=sys.stderr)


def main(argv: list[str]) -> int:
    if len(argv) == 1 and argv[0] in {"--help", "-h"}:
        print(HELP)
        return 0
    try:
        options = parse_options(
            argv,
            adapter_name="cursor-cli",
            model_env="CURSOR_MODEL",
            effort_env="CURSOR_EFFORT",
        )
    except AdapterArgumentError as exc:
        print(exc, file=sys.stderr)
        return 1

    child_env = os.environ.copy()
    try:
        session_id = read_session_id(
            options.resume_state,
            adapter="cursor-cli",
            cwd=os.getcwd(),
            model=options.model,
            effort=options.effort,
        )
    except ResumeStateError as exc:
        options.cleanup()
        print(f"cursor-cli adapter: {exc}", file=sys.stderr)
        return 1
    if session_id is not None and _chat_exists(child_env, session_id) is False:
        options.cleanup()
        print(
            f"cursor-cli adapter: resume state names Cursor chat {session_id}, but Cursor no longer stores it "
            f"under {_chats_root(child_env)}; refusing to start an empty chat under that ID",
            file=sys.stderr,
        )
        return 1

    if options.effort:
        print(
            f"cursor-cli adapter: Cursor CLI has no effort option; ignoring effort={options.effort!r} "
            "(choose the effort in the model slug, see `cursor-agent models`)",
            file=sys.stderr,
        )
    executable = _executable()
    _warn_if_untested_version(executable)

    # -p: headless. --trust: skip the workspace-trust prompt. --force: without it
    # Cursor silently rejects shell commands (the run still exits 0).
    # --approve-mcps: otherwise configured MCP servers (Specular's from `specular
    # setup` and the run's TLC tool) stay "not loaded (needs approval)".
    command = [executable, "-p", "--output-format", "stream-json", "--trust", "--force", "--approve-mcps"]
    if session_id is not None:
        # The exact chat ID captured from this logical turn; never --continue.
        command += ["--resume", session_id]
    if options.model:
        command += ["--model", options.model]
    for directory in _extra_workspace_dirs(child_env, Path.cwd()):
        command += ["--add-dir", directory]

    try:
        stream_options = _stage_prompt(options)
    except OSError as exc:
        options.cleanup()
        print(f"cursor-cli adapter: failed to stage prompt: {exc}", file=sys.stderr)
        return 1
    try:
        with _workspace_mcp(Path.cwd(), child_env):
            rc = run_json_cli("cursor-cli", command, stream_options, child_env=child_env, missing_cli_hint=INSTALL_HINT)
        if rc not in (0, 127):
            _report_failure(options.log_path)
        return rc
    finally:
        options.cleanup()
        stream_options.cleanup()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
