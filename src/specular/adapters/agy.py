"""Adapter: agy (Google Antigravity CLI).

Options:
  --prompt=...          Task prompt (mutually exclusive with --prompt-file)
  --prompt-file=FILE    Read prompt from file (mutually exclusive with --prompt)
  --max-turns=N         Accepted for launcher compatibility; ignored
  --claude-alias=NAME   Accepted for launcher compatibility; ignored
  --effort=LEVEL        Antigravity reasoning effort (default: AGY_EFFORT)
  --model=NAME          Antigravity model slug (default: AGY_MODEL)
  --log=FILE            Log file path (required)
  --resume-state=PATH   Persist/resume the exact native Antigravity conversation
  --system-prompt-file=FILE
                        Prepend FILE to the initial prompt if not already included
  --background          Accepted; caller handles backgrounding
  --help                Show this help
"""

from __future__ import annotations

import contextlib
import json
import os
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


def _write_stream_json_prompt(options: AdapterOptions) -> Path:
    """Wrap the task prompt as a single NDJSON user event for agy stdin."""
    prompt_text = options.prompt_path.read_text(encoding="utf-8", errors="replace")
    if options.system_prompt_file is not None:
        system_text = options.system_prompt_file.read_text(encoding="utf-8", errors="replace").strip()
        if system_text and system_text not in prompt_text:
            prompt_text = f"{system_text}\n\n---\n\n{prompt_text}"

    payload = {"event": "user", "message": {"content": prompt_text}}
    fd, raw_path = tempfile.mkstemp(prefix="specular-agy-stdin-", suffix=".jsonl", text=True)
    stdin_path = Path(raw_path)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as stream:
            stream.write(json.dumps(payload, ensure_ascii=False))
            stream.write("\n")
    except BaseException:
        with contextlib.suppress(OSError):
            os.close(fd)
        with contextlib.suppress(OSError):
            stdin_path.unlink()
        raise
    return stdin_path


def main(argv: list[str]) -> int:
    if len(argv) == 1 and argv[0] in {"--help", "-h"}:
        print(HELP)
        return 0
    try:
        options = parse_options(
            argv,
            adapter_name="agy",
            model_env="AGY_MODEL",
            effort_env="AGY_EFFORT",
        )
    except AdapterArgumentError as exc:
        print(exc, file=sys.stderr)
        return 1

    try:
        session_id = read_session_id(
            options.resume_state,
            adapter="agy",
            cwd=os.getcwd(),
            model=options.model,
            effort=options.effort,
        )
    except ResumeStateError as exc:
        options.cleanup()
        print(f"agy adapter: {exc}", file=sys.stderr)
        return 1

    child_env = os.environ.copy()
    command = [
        "agy",
        "--input-format",
        "stream-json",
        "--output-format",
        "stream-json",
        "--dangerously-skip-permissions",
        "--disable-slash-commands",
        "--settings",
        json.dumps({"allowNonWorkspaceAccess": True}, separators=(",", ":")),
    ]
    if session_id is not None:
        command += ["--conversation", session_id]
    if options.model:
        command += ["--model", options.model]
    if options.effort:
        command += ["--effort", options.effort]
    for directory in _extra_workspace_dirs(child_env, Path.cwd()):
        command += ["--add-dir", directory]

    try:
        stdin_path = _write_stream_json_prompt(options)
    except OSError as exc:
        options.cleanup()
        print(f"agy adapter: failed to stage prompt: {exc}", file=sys.stderr)
        return 1

    stream_options = replace(options, prompt_path=stdin_path, temporary_prompt=True)
    try:
        return run_json_cli("agy", command, stream_options, child_env=child_env)
    finally:
        options.cleanup()


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
