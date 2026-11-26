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

import os
import re
import shutil
import subprocess
import sys
import tempfile
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
    command = [executable, "-p", "--output-format", "stream-json", "--trust", "--force"]
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
        return run_json_cli("cursor-cli", command, stream_options, child_env=child_env, missing_cli_hint=INSTALL_HINT)
    finally:
        options.cleanup()
        stream_options.cleanup()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
