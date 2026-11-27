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

import base64
import contextlib
import fcntl
import hashlib
import json
import os
import re
import stat
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
_VERSION_RE = re.compile(r"^(\d{4})\.(\d{1,2})\.(\d{1,2})\b")


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


# Cursor writes meta.json when it creates a chat and keeps the messages in store.db.
_CHAT_FILES = ("meta.json", "store.db")


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
        return any((workspace / session_id / name).is_file() for workspace in root.iterdir() for name in _CHAT_FILES)
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
# server's entry is constant, so concurrent runs in one workspace agree on it:
# Cursor starts MCP servers with a minimal environment of its own, so the entry
# passes the run's launch description in one variable that the launcher
# (utils/cursor_mcp_launch.py) applies. The file holds the union of the servers
# the live runs need, and the original returns when the last one exits. The
# bookkeeping lives outside the workspace, so only mcp.json is ever touched.
TLC_WAIT_LIMIT_SECONDS = 45
LAUNCHER = Path(__file__).resolve().parent / "utils" / "cursor_mcp_launch.py"
_LAUNCHER_ENV = "SPECULAR_CURSOR_MCP_LAUNCHER"
_LAUNCH_VARIABLE = "SPECULAR_CURSOR_MCP"
# server name -> (Specular's per-run MCP JSON variable, python variable, launch-description variable)
_MCP_SERVERS = {
    "specular_tlc": ("SPECULAR_TLC_TOOL_JSON", "SPECULAR_TLC_TOOL_PYTHON", "SPECULAR_CURSOR_MCP_TLC"),
    "specular_context": ("SPECULAR_CONTEXT_MCP_JSON", "SPECULAR_CONTEXT_PYTHON", "SPECULAR_CURSOR_MCP_CONTEXT"),
}
# Context-control phases (specular.context_control.CONTEXT_CONTROL_PHASES) get the context tools.
_CONTEXT_PHASES = {"incremental", "main"}


def _mcp_entry(server: str) -> dict[str, object]:
    _, python, launch = _MCP_SERVERS[server]
    return {
        "command": f"${{env:{python}}}",
        "args": ["-I", f"${{env:{_LAUNCHER_ENV}}}"],
        "env": {_LAUNCH_VARIABLE: f"${{env:{launch}}}"},
    }


def _run_servers(env: dict[str, str]) -> list[str]:
    """Export the launch descriptions of the Specular MCP servers this run gets; return their names."""
    servers: list[str] = []
    for server, (source, python, launch) in _MCP_SERVERS.items():
        if server == "specular_context" and env.get("SPECULAR_PHASE") not in _CONTEXT_PHASES:
            continue
        try:
            entry = json.loads(env.get(source) or "null")["mcpServers"][server]
            command, args, server_env = entry["command"], entry["args"], entry.get("env", {})
        except (ValueError, KeyError, TypeError, AttributeError):
            continue
        if not (isinstance(command, str) and isinstance(args, list) and len(args) == 1 and isinstance(args[0], str)):
            continue
        if not isinstance(server_env, dict) or not all(
            isinstance(key, str) and isinstance(value, str) for key, value in server_env.items()
        ):
            continue
        server_env = dict(server_env)
        if server == "specular_tlc":
            # Cursor ends every MCP tool call after a fixed 60 s; keep each wait_tlc below it.
            server_env["SPECULAR_TLC_TOOL_WAIT_LIMIT"] = str(TLC_WAIT_LIMIT_SECONDS)
        description = json.dumps({"server": args[0], "env": server_env}, sort_keys=True)
        env[python] = command
        env[launch] = base64.b64encode(description.encode()).decode("ascii")
        servers.append(server)
    if servers:
        env[_LAUNCHER_ENV] = str(LAUNCHER)
    return servers


def _state_dir(env: dict[str, str], workspace: Path) -> Path:
    """Shared bookkeeping for one workspace, kept out of the workspace itself."""
    cache = env.get("XDG_CACHE_HOME", "").strip() or str(Path(env.get("HOME") or Path.home()) / ".cache")
    key = hashlib.sha256(str(workspace.resolve()).encode()).hexdigest()[:32]
    return Path(cache) / "specular" / "cursor-mcp" / key


def _live_servers(state: Path) -> set[str] | None:
    """Servers needed by live runs; None when no run is live.

    Each run holds an exclusive lock on its marker, which lists its servers; a
    marker whose lock can be taken belongs to a run that has exited.
    """
    live: set[str] | None = None
    for marker in state.glob("run-*"):
        try:
            fd = os.open(marker, os.O_RDONLY)
        except OSError:
            continue
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                names = os.read(fd, 65536).decode(errors="replace").split()
                live = (live or set()) | {name for name in names if name in _MCP_SERVERS}
            else:
                marker.unlink(missing_ok=True)
        finally:
            os.close(fd)
    return live


def _replace_file(path: Path, data: bytes) -> None:
    """Atomically replace ``path``, keeping its permissions (new files follow the umask)."""
    try:
        mode = stat.S_IMODE(path.stat().st_mode)
    except FileNotFoundError:
        umask = os.umask(0)
        os.umask(umask)
        mode = 0o666 & ~umask
    fd, raw = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
            os.fchmod(stream.fileno(), mode)
        os.replace(raw, path)
    except BaseException:
        Path(raw).unlink(missing_ok=True)
        raise


def _load_config(saved: bytes) -> dict[str, object]:
    try:
        base = json.loads(saved[1:].decode()) if saved[:1] == b"1" else {}
    except ValueError:
        base = {}
    return dict(base) if isinstance(base, dict) else {}


def _merged_config(saved: bytes, servers: set[str]) -> bytes:
    """The user's workspace MCP config (from the backup) plus the Specular servers."""
    base = _load_config(saved)
    existing = base.get("mcpServers")
    base["mcpServers"] = {
        **(existing if isinstance(existing, dict) else {}),
        **{server: _mcp_entry(server) for server in sorted(servers)},
    }
    return (json.dumps(base, indent=2) + "\n").encode()


def _original_config(current: bytes | None, backup: bytes | None) -> bytes:
    """The user's own config while no run is live (b"0" = no file, b"1" + bytes).

    A run killed while it held the file leaves its entries (and a backup)
    behind. Strip exactly those entries; anything else in the file is the
    user's, including edits made after the killed run, so it is kept.
    """
    if current is None:
        return b"0"
    try:
        parsed = json.loads(current.decode())
    except (UnicodeError, ValueError):
        return b"1" + current
    servers = parsed.get("mcpServers") if isinstance(parsed, dict) else None
    if not isinstance(servers, dict):
        return b"1" + current
    ours = {name for name in _MCP_SERVERS if servers.get(name) == _mcp_entry(name)}
    if not ours:
        return b"1" + current
    stripped = {**parsed, "mcpServers": {k: v for k, v in servers.items() if k not in ours}}
    if backup is not None and (backup == b"0" or backup[:1] == b"1"):
        if backup == b"0" and stripped == {"mcpServers": {}}:
            return b"0"
        if backup[:1] == b"1" and _load_config(backup) == stripped:
            return backup
    return b"1" + (json.dumps(stripped, indent=2) + "\n").encode()


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
    if directory.is_symlink() or config_path.is_symlink():
        print(
            f"cursor-cli adapter: {config_path} is a symbolic link; not adding Specular's MCP servers to it "
            "(the agent can still use the equivalent shell scripts)",
            file=sys.stderr,
        )
        yield []
        return
    state = _state_dir(env, cwd)
    backup = state / "original"
    created_marker = state / "created-directory"
    with _state_lock(state):
        live = _live_servers(state)
        if live is None:
            current = config_path.read_bytes() if config_path.is_file() else None
            saved = backup.read_bytes() if backup.is_file() else None
            backup.write_bytes(_original_config(current, saved))
            if not directory.is_dir():
                directory.mkdir()
                created_marker.touch()
        needed = (live or set()) | set(servers)
        if needed != live:
            _replace_file(config_path, _merged_config(backup.read_bytes(), needed))
        marker = state / f"run-{os.getpid()}-{os.urandom(4).hex()}"
        marker_fd = os.open(marker, os.O_RDWR | os.O_CREAT | os.O_TRUNC, 0o600)
        fcntl.flock(marker_fd, fcntl.LOCK_EX)
        os.write(marker_fd, ("\n".join(servers) + "\n").encode())
    try:
        yield servers
    finally:
        with _state_lock(state):
            marker.unlink(missing_ok=True)
            os.close(marker_fd)
            live = _live_servers(state)
            if live is not None:
                _replace_file(config_path, _merged_config(backup.read_bytes(), live))
            else:
                saved = backup.read_bytes() if backup.exists() else b"0"
                if saved[:1] == b"1":
                    _replace_file(config_path, saved[1:])
                else:
                    config_path.unlink(missing_ok=True)
                if created_marker.exists():
                    with contextlib.suppress(OSError):
                        directory.rmdir()
                backup.unlink(missing_ok=True)
                created_marker.unlink(missing_ok=True)
                # Waiting runs notice the removed lock and start over (see _state_lock).
                with contextlib.suppress(OSError):
                    (state / "lock").unlink()
                    state.rmdir()


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
    executable = "cursor-agent"
    _warn_if_untested_version(executable)

    # -p: headless. --trust: skip the workspace-trust prompt. --force: without it
    # Cursor silently rejects shell commands (the run still exits 0).
    # --approve-mcps: otherwise configured MCP servers (Specular's from `specular
    # setup` and the run's TLC tool) stay "not loaded (needs approval)".
    # --stream-partial-output: in whole-message mode Cursor joins the text the
    # agent writes after a background command finishes onto its previous
    # message without a separator, hiding the boundary (and a final VERDICT line).
    command = [
        executable,
        "-p",
        "--output-format",
        "stream-json",
        "--stream-partial-output",
        "--trust",
        "--force",
        "--approve-mcps",
    ]
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
            return run_json_cli("cursor-cli", command, stream_options, child_env=child_env)
    finally:
        options.cleanup()
        stream_options.cleanup()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
