"""Unit tests for the Cursor CLI (cursor-cli) adapter.

The stream fixtures under fixtures/cursor-cli/ are recorded Cursor CLI
2026.11.22-e9042b2 `stream-json` output (paths and prose sanitized). Invocation
tests put a fake `cursor-agent` first on PATH.
"""

from __future__ import annotations

import hashlib
import json
import os
import stat
import subprocess
import sys
from pathlib import Path

import pytest

from specular.adapters.utils.event_stream import stream_events
from specular.adapters.utils.policy import POLICY_BLOCKED_RC
from specular.adapters.utils.transient import TRANSIENT_FAILURE_RC
from specular.adapters.utils.usage import UsageTotals
from specular.skill_refs import materialize_skill_refs, prompt_skill_ids

REPO_ROOT = Path(__file__).resolve().parents[2]
ADAPTER_SH = REPO_ROOT / "scripts/launch/adapters/cursor-cli.sh"
ADAPTER_PY = REPO_ROOT / "src/specular/adapters/cursor_cli.py"
FIXTURES = Path(__file__).parent / "fixtures/cursor-cli"
RATE_LIMIT_RC = 75
SESSION = "8da3b009-4d34-436f-ae86-081f11d665b8"


def _lines(name: str) -> list[bytes]:
    return [line.encode() + b"\n" for line in (FIXTURES / name).read_text(encoding="utf-8").splitlines()]


# ── Event stream ────────────────────────────────────────────────────────────


def test_recorded_tool_stream_renders_log_usage_and_session(tmp_path: Path) -> None:
    activity = tmp_path / "agent.activity.jsonl"
    log = tmp_path / "agent.log"
    status = stream_events("cursor-cli", activity, log, _lines("tools-success.jsonl"))

    assert status.successful_terminal is True
    assert status.terminal_error is None
    assert status.structured_error is None
    assert status.session_id == "e4d69556-c809-46bb-985c-afbf55440e62"
    assert log.read_text(encoding="utf-8").splitlines() == [
        "Reading `a.txt` and running the shell command.",
        "reading /work/a.txt",
        "running echo shell-ok",
        "editing /work/b.txt",
        "DONE",
    ]
    assert status.usage["total_cost_usd"] is None  # Cursor reports no cost: usage is incomplete
    assert status.usage["usage"] == {
        "input_tokens": 11168,
        "cached_input_tokens": 34304,
        "cache_write_input_tokens": 0,
        "output_tokens": 222,
        "reasoning_output_tokens": 130,  # already inside output_tokens
        "total_tokens": 11168 + 34304 + 222,
    }
    assert UsageTotals.from_payload(status.usage).as_usage() == status.usage["usage"]

    # Completed successful tool calls replay file contents and command output;
    # they are dropped from the activity sidecar, their `started` events kept.
    records = [json.loads(line) for line in activity.read_text(encoding="utf-8").splitlines()]
    tool_records = [record for record in records if record["type"] == "tool_call"]
    assert [record["subtype"] for record in tool_records] == ["started"] * 3
    assert records[-1]["type"] == "result"


def test_recorded_builtin_tools_have_specific_log_lines(tmp_path: Path) -> None:
    # Read, Grep, Glob, Write/Edit, Delete, Shell (pipe and background), AwaitShell,
    # TodoWrite, WebFetch and Task, recorded in one headless run.
    log = tmp_path / "agent.log"
    status = stream_events("cursor-cli", tmp_path / "a.jsonl", log, _lines("builtin-tools.jsonl"))
    assert status.successful_terminal is True
    lines = log.read_text(encoding="utf-8").splitlines()
    assert lines[0] == "Working through the steps in order."
    assert lines[1:12] == [
        "reading /work/data.txt",
        "searching for beta",
        "searching for *.txt",
        "editing /work/notes.md",  # write then edit; repeated lines are collapsed
        "deleting /work/remove-me.txt",
        "running printf 'a\\nb\\n' | wc -l > count.txt && cat count.txt",
        "running sleep 3 && echo bg-done > bg.txt",
        "waiting for a background shell command",
        "using updateTodos",
        "using webFetch: https://example.com",
        "spawning subagent: Count data.txt lines",
    ]
    assert not any("getMcpTools" in line for line in lines)


def test_text_after_a_background_task_starts_a_new_line(tmp_path: Path) -> None:
    # Recorded with --stream-partial-output: the agent ends with "VERDICT: OK" while
    # a background command runs; when it finishes Cursor resumes the agent, which
    # keeps writing into the same message (the result text shows them joined).
    lines = _lines("background-task-partial.jsonl")
    assert "VERDICT: OKThe background command finished" in json.loads(lines[-1])["result"]
    log = tmp_path / "agent.log"
    status = stream_events("cursor-cli", tmp_path / "a.jsonl", log, lines)
    assert status.successful_terminal is True
    rendered = log.read_text(encoding="utf-8").splitlines()
    assert "VERDICT: OK" in rendered
    assert rendered[-1].startswith("The background command finished successfully")
    assert sum("VERDICT: OK" in line for line in rendered) == 1  # repeated whole messages are not re-logged


def test_whole_message_events_are_logged_without_deltas(tmp_path: Path) -> None:
    lines = [
        json.dumps({"type": "assistant", "session_id": "s", "message": {"content": [{"type": "text", "text": "a"}]}}),
        json.dumps(
            {
                "type": "assistant",
                "session_id": "s",
                "model_call_id": "m",
                "timestamp_ms": 1,
                "message": {"content": [{"type": "text", "text": "b"}]},
            }
        ),
        json.dumps({"type": "result", "subtype": "success", "result": "ab", "session_id": "s"}),
    ]
    log = tmp_path / "agent.log"
    stream_events("cursor-cli", tmp_path / "a.jsonl", log, [line.encode() + b"\n" for line in lines])
    assert log.read_text().splitlines() == ["a", "b"]


def test_rejected_tool_call_is_reported(tmp_path: Path) -> None:
    activity = tmp_path / "agent.activity.jsonl"
    log = tmp_path / "agent.log"
    status = stream_events("cursor-cli", activity, log, _lines("shell-rejected.jsonl"))

    rendered = log.read_text(encoding="utf-8")
    assert status.successful_terminal is True
    assert rendered.count("adapter tool error: shell: rejected by Cursor permissions") == 2
    # Rejections stay in the sidecar so a permission problem is diagnosable.
    records = [json.loads(line) for line in activity.read_text().splitlines()]
    completed = [json.dumps(r) for r in records if r["type"] == "tool_call" and r["subtype"] == "completed"]
    assert len(completed) == 2 and all("rejected" in line for line in completed)


def test_failed_shell_command_reports_its_exit_code(tmp_path: Path) -> None:
    completed = {
        "type": "tool_call",
        "subtype": "completed",
        "session_id": "s",
        "tool_call": {
            "shellToolCall": {
                "args": {"command": "gh issue view 1"},
                "result": {"failure": {"command": "gh issue view 1", "exitCode": 1, "stdout": "", "stderr": "x"}},
            }
        },
    }
    stream_events("cursor-cli", tmp_path / "a.jsonl", tmp_path / "a.log", [json.dumps(completed).encode()])
    assert (tmp_path / "a.log").read_text().strip() == "adapter tool error: shell: exit code 1"


def test_resumed_stream_keeps_the_same_session(tmp_path: Path) -> None:
    status = stream_events("cursor-cli", tmp_path / "a.jsonl", tmp_path / "a.log", _lines("resume.jsonl"))
    assert status.successful_terminal is True
    assert status.session_id == "e4d69556-c809-46bb-985c-afbf55440e62"
    assert (tmp_path / "a.log").read_text().strip() == "b.txt"


def test_stream_without_result_fails(tmp_path: Path) -> None:
    lines = _lines("tools-success.jsonl")[:-1]
    status = stream_events("cursor-cli", tmp_path / "a.jsonl", tmp_path / "a.log", lines)
    assert status.successful_terminal is False
    assert status.terminal_error == "stream ended without a Cursor result event"


def test_failed_result_is_a_structured_error(tmp_path: Path) -> None:
    record = {"type": "result", "subtype": "error", "is_error": True, "result": "Model call failed", "session_id": "s"}
    status = stream_events("cursor-cli", tmp_path / "a.jsonl", tmp_path / "a.log", [json.dumps(record).encode()])
    assert status.successful_terminal is False
    assert status.structured_error == "Model call failed"
    assert "final Cursor result was 'error'" in str(status.terminal_error)
    assert "adapter error: Model call failed" in (tmp_path / "a.log").read_text()


def test_mcp_tool_call_is_named_by_server_and_tool(tmp_path: Path) -> None:
    started = {
        "type": "tool_call",
        "subtype": "started",
        "session_id": "s",
        "tool_call": {
            "mcpToolCall": {
                "args": {"name": "specular_tlc-wait_tlc", "providerIdentifier": "specular_tlc", "toolName": "wait_tlc"}
            }
        },
    }
    status = stream_events("cursor-cli", tmp_path / "a.jsonl", tmp_path / "a.log", [json.dumps(started).encode()])
    assert status.session_id == "s"
    assert (tmp_path / "a.log").read_text().strip() == "using specular_tlc.wait_tlc"


def test_malformed_and_oversized_lines_do_not_break_the_stream(tmp_path: Path) -> None:
    lines = [
        b"not json at all\n",
        b"{truncated json\n",
        json.dumps({"type": "assistant", "message": {"content": [{"type": "text", "text": "x" * 500_000}]}}).encode()
        + b"\n",
        *_lines("resume.jsonl"),
    ]
    status = stream_events("cursor-cli", tmp_path / "a.jsonl", tmp_path / "a.log", lines)
    assert status.successful_terminal is True
    assert status.plain_diagnostics[:2] == ("not json at all\n", "{truncated json\n")


# ── Adapter invocation (fake cursor-agent) ──────────────────────────────────


def _fake_cli(bin_dir: Path, body: str, *, version: str = "2026.11.22-e9042b2") -> None:
    """Install a fake `cursor-agent`; it answers `--version` and otherwise runs ``body``."""
    bin_dir.mkdir(parents=True, exist_ok=True)
    fake = bin_dir / "cursor-agent"
    fake.write_text(
        f"#!{sys.executable}\n"
        "import json, os, sys\n"
        f"if sys.argv[1:] == ['--version']:\n    print({version!r}); raise SystemExit(0)\n"
        f"{body}\n",
        encoding="utf-8",
    )
    fake.chmod(fake.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _recording_cli(bin_dir: Path, capture: Path, *, session: str = SESSION, text: str = "DONE_OK") -> None:
    """A fake that records argv/stdin/env, creates its chat like Cursor, and succeeds."""
    _fake_cli(
        bin_dir,
        f"""
stdin = sys.stdin.read()
mcp = os.path.join(os.getcwd(), ".cursor", "mcp.json")
json.dump({{
    "argv": sys.argv[1:],
    "stdin": stdin,
    "stdin_sha256": __import__("hashlib").sha256(stdin.encode()).hexdigest(),
    "mcp": open(mcp).read() if os.path.exists(mcp) else None,
    "env": {{k: v for k, v in os.environ.items() if k.startswith(("SPECULAR_TLC_TOOL_", "CURSOR_"))}},
}}, open({str(capture)!r}, "w"))
chat = os.path.join(os.environ["CURSOR_CONFIG_DIR"], "chats", "0123abcd", {session!r})
os.makedirs(chat, exist_ok=True)
open(os.path.join(chat, "meta.json"), "w").write("{{}}")
sid = {session!r}
print(json.dumps({{"type": "system", "subtype": "init", "session_id": sid, "model": "Grok 4.7 256K Low"}}))
print(json.dumps({{"type": "assistant", "message": {{"role": "assistant", "content": [{{"type": "text", "text": {text!r}}}]}}, "session_id": sid}}))
print(json.dumps({{"type": "result", "subtype": "success", "is_error": False, "result": {text!r}, "session_id": sid,
    "usage": {{"inputTokens": 10, "outputTokens": 3, "cacheReadTokens": 5, "cacheWriteTokens": 1, "reasoningTokens": 2}}}}))
""",
    )


def _env(tmp_path: Path, bin_dir: Path, **extra: str) -> dict[str, str]:
    env = {
        key: value
        for key, value in os.environ.items()
        if not key.startswith(("CURSOR_", "SPECULAR_TLC_TOOL_", "SPECULAR_TARGET", "SPECULAR_WORK"))
    }
    env["PATH"] = f"{bin_dir}{os.pathsep}{env.get('PATH', '')}"
    env["CURSOR_CONFIG_DIR"] = str(tmp_path / "cursor-config")
    env.update(extra)
    return env


def _run(argv: list[str], env: dict[str, str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(ADAPTER_SH), *argv], env=env, cwd=cwd, capture_output=True, text=True, check=False)


def test_invocation_rules_resume_and_usage(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    target = tmp_path / "target-repo"
    target.mkdir()
    rules = tmp_path / "rules.md"
    rules.write_text("NEVER SKIP CHECKS", encoding="utf-8")
    env = _env(tmp_path, bin_dir, CURSOR_MODEL="grok-4.7-low", SPECULAR_TARGET_REPO_DIR=str(target))
    log, state = tmp_path / "phase.log", tmp_path / "resume.json"

    first = _run(
        ["--prompt=Check invariant", f"--system-prompt-file={rules}", f"--log={log}", f"--resume-state={state}"],
        env,
        tmp_path,
    )
    assert first.returncode == 0, first.stderr
    recorded = json.loads(capture.read_text())
    argv = recorded["argv"]
    assert argv[:8] == [
        "-p",
        "--output-format",
        "stream-json",
        "--stream-partial-output",
        "--trust",
        "--force",
        "--approve-mcps",
        "--model",
    ]
    assert argv[argv.index("--model") + 1] == "grok-4.7-low"
    added = [argv[index + 1] for index, arg in enumerate(argv) if arg == "--add-dir"]
    assert added == [str(REPO_ROOT), str(target.resolve())]  # Specular root and the target repository
    assert "--resume" not in argv and "--continue" not in argv
    assert not any("Check invariant" in arg for arg in argv)  # the prompt travels on stdin only
    assert recorded["stdin"] == "NEVER SKIP CHECKS\n\n---\n\nCheck invariant"
    assert log.read_text().strip() == "DONE_OK"
    assert json.loads(state.read_text())["session_id"] == SESSION
    usage = json.loads(log.with_suffix(".usage.json").read_text())
    assert usage["agent"] == "cursor-cli" and usage["session_id"] == SESSION and usage["total_cost_usd"] is None
    assert usage["usage"]["total_tokens"] == 10 + 5 + 1 + 3

    # A resume continues the exact chat and does not duplicate the rules.
    second = _run(
        [
            "--prompt=NEVER SKIP CHECKS\n\nContinue",
            f"--system-prompt-file={rules}",
            f"--log={log}",
            f"--resume-state={state}",
        ],
        env,
        tmp_path,
    )
    assert second.returncode == 0, second.stderr
    argv = json.loads(capture.read_text())["argv"]
    assert argv[argv.index("--resume") + 1] == SESSION
    assert "--continue" not in argv
    assert json.loads(capture.read_text())["stdin"].count("NEVER SKIP CHECKS") == 1


def test_resume_of_a_vanished_chat_is_refused(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    env = _env(tmp_path, bin_dir)
    log, state = tmp_path / "phase.log", tmp_path / "resume.json"
    assert _run(["--prompt=first", f"--log={log}", f"--resume-state={state}"], env, tmp_path).returncode == 0
    capture.unlink()
    for meta in (tmp_path / "cursor-config/chats").glob(f"*/{SESSION}/meta.json"):
        meta.unlink()

    refused = _run(["--prompt=again", f"--log={log}", f"--resume-state={state}"], env, tmp_path)
    assert refused.returncode == 1
    assert f"Cursor chat {SESSION}" in refused.stderr and "refusing to start an empty chat" in refused.stderr
    assert not capture.exists()  # Cursor was never started


def test_resume_into_a_different_chat_fails(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture, session="other-chat")
    env = _env(tmp_path, bin_dir)
    state = tmp_path / "resume.json"
    chat = tmp_path / "cursor-config/chats/0123abcd" / SESSION
    chat.mkdir(parents=True)
    (chat / "meta.json").write_text("{}")
    state.write_text(
        json.dumps(
            {
                "version": 1,
                "adapter": "cursor-cli",
                "session_id": SESSION,
                "cwd": os.path.realpath(tmp_path),
                "model": "",
                "effort": "",
            }
        )
    )
    result = _run(["--prompt=continue", f"--log={tmp_path / 'p.log'}", f"--resume-state={state}"], env, tmp_path)
    assert result.returncode == 1
    assert "changed session ID" in result.stderr
    assert json.loads(state.read_text())["session_id"] == SESSION


@pytest.mark.parametrize(
    ("field", "value"),
    [("adapter", "agy"), ("model", "grok-4.7-high"), ("effort", "high"), ("cwd", "/elsewhere")],
)
def test_mismatched_resume_state_is_rejected_before_launch(tmp_path: Path, field: str, value: str) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    state = tmp_path / "resume.json"
    payload = {
        "version": 1,
        "adapter": "cursor-cli",
        "session_id": SESSION,
        "cwd": os.path.realpath(tmp_path),
        "model": "grok-4.7-low",
        "effort": "",
    }
    payload[field] = value
    state.write_text(json.dumps(payload))
    result = _run(
        ["--prompt=x", "--model=grok-4.7-low", f"--log={tmp_path / 'p.log'}", f"--resume-state={state}"],
        _env(tmp_path, bin_dir),
        tmp_path,
    )
    assert result.returncode == 1
    assert result.stderr.startswith("cursor-cli adapter: resume state")
    assert not capture.exists()


@pytest.mark.parametrize("session_id", ["-rf", " padded ", "bad\x01id"])
def test_unsafe_session_ids_are_rejected(tmp_path: Path, session_id: str) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    state = tmp_path / "resume.json"
    state.write_text(
        json.dumps(
            {
                "version": 1,
                "adapter": "cursor-cli",
                "session_id": session_id,
                "cwd": os.path.realpath(tmp_path),
                "model": "",
                "effort": "",
            }
        )
    )
    result = _run(
        ["--prompt=x", f"--log={tmp_path / 'p.log'}", f"--resume-state={state}"], _env(tmp_path, bin_dir), tmp_path
    )
    assert result.returncode == 1 and not capture.exists()


def test_large_prompt_reaches_stdin_intact(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    prompt = tmp_path / "prompt.md"
    text = "".join(f"line {index} of a large Specular prompt\n" for index in range(60_000))  # ~2 MB
    prompt.write_text(text, encoding="utf-8")
    result = _run([f"--prompt-file={prompt}", f"--log={tmp_path / 'p.log'}"], _env(tmp_path, bin_dir), tmp_path)
    assert result.returncode == 0, result.stderr
    recorded = json.loads(capture.read_text())
    assert recorded["stdin_sha256"] == hashlib.sha256(text.encode()).hexdigest()
    assert all(len(arg) < 4096 for arg in recorded["argv"])


def test_model_and_effort_options(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    env = _env(tmp_path, bin_dir, CURSOR_MODEL="grok-4.7-low", CURSOR_EFFORT="high")
    log = tmp_path / "p.log"

    result = _run(["--prompt=x", f"--log={log}"], env, tmp_path)
    assert result.returncode == 0, result.stderr
    recorded = json.loads(capture.read_text())
    assert recorded["argv"][recorded["argv"].index("--model") + 1] == "grok-4.7-low"
    assert "--effort" not in recorded["argv"]
    assert "Cursor CLI has no effort option; ignoring effort='high'" in result.stderr
    assert "CURSOR_MODEL" not in recorded["env"] and "CURSOR_EFFORT" not in recorded["env"]

    # An explicit empty value clears the environment fallback.
    result = _run(["--prompt=x", "--model=", "--effort=", f"--log={log}"], env, tmp_path)
    assert result.returncode == 0, result.stderr
    assert "--model" not in json.loads(capture.read_text())["argv"]
    assert "effort" not in result.stderr


def test_options_help_and_errors(tmp_path: Path) -> None:
    env = _env(tmp_path, tmp_path / "bin")
    shown = _run(["--help"], env, tmp_path)
    assert shown.returncode == 0 and "Adapter: cursor-cli" in shown.stdout and "cursor-agent models" in shown.stdout
    for argv, message in (
        (["--prompt=x"], "--log is required"),
        ([f"--log={tmp_path / 'l'}"], "one of --prompt or --prompt-file is required"),
        (["--prompt=x", "--prompt-file=y", f"--log={tmp_path / 'l'}"], "mutually exclusive"),
        (["--prompt=x", f"--log={tmp_path / 'l'}", "--bogus"], "unknown option: --bogus"),
        (["--prompt-file=/nonexistent", f"--log={tmp_path / 'l'}"], "prompt file not found"),
    ):
        result = _run(argv, env, tmp_path)
        assert result.returncode == 1 and result.stderr.startswith("cursor-cli adapter:"), (argv, result.stderr)
        assert message in result.stderr


def test_ignored_launcher_options_are_accepted(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    result = _run(
        ["--prompt=x", "--max-turns=30", "--claude-alias=claude", "--background", f"--log={tmp_path / 'p.log'}"],
        _env(tmp_path, bin_dir),
        tmp_path,
    )
    assert result.returncode == 0, result.stderr
    assert not any(
        arg.startswith(("--max-turns", "--claude-alias", "--background"))
        for arg in json.loads(capture.read_text())["argv"]
    )


def test_missing_cli_reports_install_hint(tmp_path: Path) -> None:
    log = tmp_path / "p.log"
    env = _env(tmp_path, tmp_path / "empty-bin")
    env["PATH"] = str(tmp_path / "empty-bin")
    result = subprocess.run(
        [sys.executable, str(ADAPTER_PY), "--prompt=x", f"--log={log}"],
        env=env,
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 127
    assert "failed to launch cursor-agent" in result.stderr and "cursor.com/install" in result.stderr
    assert "cursor.com/install" in log.read_text()
    assert json.loads(log.with_suffix(".usage.json").read_text())["agent"] == "cursor-cli"


def test_older_cli_version_warns(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    _fake_cli(
        bin_dir,
        'sys.stdin.read(); print(json.dumps({"type": "result", "subtype": "success", "result": "ok", "session_id": "s"}))',
        version="2026.01.05-abcdef0",
    )
    result = _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], _env(tmp_path, bin_dir), tmp_path)
    assert result.returncode == 0
    assert "older than the oldest tested version 2026.11.22" in result.stderr


def test_api_key_is_never_written_to_logs(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    secret = "key_" + "s3cr3t" * 6
    log = tmp_path / "p.log"
    env = _env(tmp_path, bin_dir, CURSOR_API_KEY=secret, SPECULAR_ACTIVITY_LOG=str(tmp_path / "p.activity.jsonl"))
    assert _run(["--prompt=x", f"--log={log}"], env, tmp_path).returncode == 0
    assert json.loads(capture.read_text())["env"]["CURSOR_API_KEY"] == secret  # passed to Cursor via env only
    assert secret not in " ".join(json.loads(capture.read_text())["argv"])
    for path in (log, log.with_suffix(".usage.json"), tmp_path / "p.activity.jsonl"):
        assert secret not in path.read_text()


# ── Failure classification ──────────────────────────────────────────────────


def _failing_cli(
    bin_dir: Path, stderr_lines: list[str], exit_code: int = 1, events: list[dict[str, object]] | None = None
) -> None:
    _fake_cli(
        bin_dir,
        "sys.stdin.read()\n"
        f"for event in {events or []!r}:\n    print(json.dumps(event), flush=True)\n"
        f"for line in {stderr_lines!r}:\n    print(line, file=sys.stderr, flush=True)\n"
        f"raise SystemExit({exit_code})",
    )


@pytest.mark.parametrize(
    ("stderr_lines", "expected_rc", "stderr_hint"),
    [
        # Verbatim Cursor CLI 2026.11.22 diagnostics.
        (
            [
                "Error: Authentication required. Please run 'agent login' first, or set CURSOR_API_KEY environment variable."
            ],
            1,
            "authenticate with `cursor-agent login` or set CURSOR_API_KEY",
        ),
        (
            ["\x1b[33m⚠ Warning: The provided API key is invalid.\x1b[0m", "Please check you have the right key."],
            1,
            "",
        ),
        (["Cannot use this model: nope. Available models: auto, grok-4.7-low"], 1, "cursor-agent models"),
        # Provider failures in the CLI's own text (not yet observed verbatim).
        (["Error: 429 Too Many Requests: rate limit exceeded"], RATE_LIMIT_RC, ""),
        (["Error: HTTP 503 service unavailable"], TRANSIENT_FAILURE_RC, ""),
        (["Error: output blocked by content filtering policy"], POLICY_BLOCKED_RC, ""),
    ],
)
def test_cli_diagnostics_are_classified(
    tmp_path: Path, stderr_lines: list[str], expected_rc: int, stderr_hint: str
) -> None:
    bin_dir = tmp_path / "bin"
    _failing_cli(bin_dir, stderr_lines)
    result = _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], _env(tmp_path, bin_dir), tmp_path)
    assert result.returncode == expected_rc, result.stderr
    if stderr_hint:
        assert stderr_hint in result.stderr


def test_auth_failure_is_reported_clearly(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    _failing_cli(bin_dir, ["Error: Authentication required. Please run 'agent login' first."])
    result = _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], _env(tmp_path, bin_dir), tmp_path)
    assert result.returncode == 1
    assert result.stderr.startswith("cursor-cli adapter: Error: Authentication required.")


def test_failed_result_text_is_classified(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    failed = {
        "type": "result",
        "subtype": "error",
        "is_error": True,
        "result": "429 rate limit exceeded",
        "session_id": "s",
    }
    _failing_cli(bin_dir, [], exit_code=1, events=[failed])
    result = _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], _env(tmp_path, bin_dir), tmp_path)
    assert result.returncode == RATE_LIMIT_RC


def test_agent_text_quoting_provider_errors_is_not_classified(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    quoted = {
        "type": "assistant",
        "session_id": "s",
        "message": {
            "content": [{"type": "text", "text": "The replica hit HTTP 503 service unavailable and 429 rate limit"}]
        },
    }
    # A crash after agent prose: the CLI's last line is the agent's JSON, not a diagnostic.
    _failing_cli(bin_dir, [], exit_code=1, events=[quoted])
    result = _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], _env(tmp_path, bin_dir), tmp_path)
    assert result.returncode == 1
    # Successful completion quoting the same text stays successful.
    _recording_cli(bin_dir, tmp_path / "capture.json", text="Fixed: HTTP 503 service unavailable, 429 rate limit")
    result = _run(["--prompt=x", f"--log={tmp_path / 'q.log'}"], _env(tmp_path, bin_dir), tmp_path)
    assert result.returncode == 0, result.stderr


def test_native_specular_status_codes_are_not_passed_through(tmp_path: Path) -> None:
    for native in (74, 72):
        bin_dir = tmp_path / f"bin{native}"
        _failing_cli(bin_dir, ["something unrelated broke"], exit_code=native)
        result = _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], _env(tmp_path, bin_dir), tmp_path)
        assert result.returncode == 1


# ── Workspace MCP registration ──────────────────────────────────────────────


def _tlc_tool_json(tmp_path: Path) -> str:
    entry = {"command": "/opt/tlc/python", "args": ["/opt/specular/tools/tlc_tools/mcp_server.py"], "env": {"A": "1"}}
    return json.dumps({"mcpServers": {"specular_tlc": {**entry, "tools": ["*"], "timeout": 1000}}})


def test_tlc_tool_is_registered_for_the_run_and_removed_after(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    workspace = tmp_path / "ws"
    workspace.mkdir()
    env = _env(tmp_path, bin_dir, SPECULAR_TLC_TOOL_JSON=_tlc_tool_json(tmp_path))
    result = _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], env, workspace)
    assert result.returncode == 0, result.stderr

    recorded = json.loads(capture.read_text())
    assert "--approve-mcps" in recorded["argv"]
    assert json.loads(recorded["mcp"]) == {
        "mcpServers": {
            "specular_tlc": {"command": "${env:SPECULAR_TLC_TOOL_PYTHON}", "args": ["${env:SPECULAR_TLC_TOOL_SERVER}"]}
        }
    }
    assert recorded["env"]["SPECULAR_TLC_TOOL_PYTHON"] == "/opt/tlc/python"
    assert recorded["env"]["SPECULAR_TLC_TOOL_SERVER"] == "/opt/specular/tools/tlc_tools/mcp_server.py"
    assert recorded["env"]["SPECULAR_TLC_TOOL_WAIT_LIMIT"] == "45"  # under Cursor's fixed 60 s tool-call limit
    assert list(workspace.iterdir()) == []  # the workspace is left exactly as found


def test_user_workspace_mcp_config_is_kept_and_restored(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    workspace = tmp_path / "ws"
    (workspace / ".cursor").mkdir(parents=True)
    original = b'{\n  "mcpServers": {"mine": {"command": "my-server"}},\n  "other": 1\n}\n'
    (workspace / ".cursor/mcp.json").write_bytes(original)

    env = _env(tmp_path, bin_dir, SPECULAR_TLC_TOOL_JSON=_tlc_tool_json(tmp_path))
    assert _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], env, workspace).returncode == 0
    during = json.loads(json.loads(capture.read_text())["mcp"])
    assert set(during["mcpServers"]) == {"mine", "specular_tlc"} and during["other"] == 1
    assert (workspace / ".cursor/mcp.json").read_bytes() == original
    assert sorted(path.name for path in (workspace / ".cursor").iterdir()) == ["mcp.json"]


def test_config_left_by_a_killed_run_is_restored(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    workspace = tmp_path / "ws"
    state = workspace / ".cursor/.specular-mcp"
    state.mkdir(parents=True)
    # A run (pid 2**22+1 cannot be alive) died holding a modified file.
    (state / "original").write_bytes(b'1{"mcpServers": {"mine": {"command": "x"}}}')
    (state / f"run-{2**22 + 1}-dead").touch()
    (workspace / ".cursor/mcp.json").write_text('{"mcpServers": {"specular_tlc": {}, "mine": {"command": "x"}}}')

    env = _env(tmp_path, bin_dir, SPECULAR_TLC_TOOL_JSON=_tlc_tool_json(tmp_path))
    assert _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], env, workspace).returncode == 0
    assert (workspace / ".cursor/mcp.json").read_text() == '{"mcpServers": {"mine": {"command": "x"}}}'
    assert not state.exists()


def test_concurrent_runs_share_one_registration(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    # Each fake run blocks until both have started, so their lifetimes overlap.
    _fake_cli(
        bin_dir,
        f"""
import time
sys.stdin.read()
barrier = {str(tmp_path / "barrier")!r}
open(barrier + "." + str(os.getpid()), "w").close()
deadline = time.time() + 20
while len([p for p in os.listdir({str(tmp_path)!r}) if p.startswith("barrier.")]) < 2 and time.time() < deadline:
    time.sleep(0.05)
assert '"specular_tlc"' in open(".cursor/mcp.json").read()
print(json.dumps({{"type": "result", "subtype": "success", "result": "ok", "session_id": "s" + str(os.getpid())}}))
""",
    )
    workspace = tmp_path / "ws"
    workspace.mkdir()
    env = _env(tmp_path, bin_dir, SPECULAR_TLC_TOOL_JSON=_tlc_tool_json(tmp_path))
    runs = [
        subprocess.Popen(
            [str(ADAPTER_SH), "--prompt=x", f"--log={tmp_path / f'p{index}.log'}"],
            env=env,
            cwd=workspace,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        for index in range(2)
    ]
    for run in runs:
        _, stderr = run.communicate(timeout=60)
        assert run.returncode == 0, stderr
    assert list(workspace.iterdir()) == []


def _context_mcp_json() -> str:
    entry = {"command": "/ctx/python", "args": ["/specular/tools/context_control/mcp_server.py"], "env": {}}
    return json.dumps({"mcpServers": {"specular_context": entry}})


@pytest.mark.parametrize(("phase", "expected"), [("main", True), ("incremental", True), ("spec_validation", False)])
def test_context_tools_are_registered_only_for_context_phases(tmp_path: Path, phase: str, expected: bool) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    env = _env(
        tmp_path,
        bin_dir,
        SPECULAR_PHASE=phase,
        SPECULAR_CONTEXT_MCP_JSON=_context_mcp_json(),
        SPECULAR_TLC_TOOL_JSON=_tlc_tool_json(tmp_path),
    )
    assert _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], env, tmp_path).returncode == 0
    recorded = json.loads(capture.read_text())
    servers = json.loads(recorded["mcp"])["mcpServers"]
    assert ("specular_context" in servers) is expected and "specular_tlc" in servers
    if expected:
        assert recorded["env"]["SPECULAR_TLC_TOOL_WAIT_LIMIT"] == "45"
        assert json.loads(capture.read_text())["env"].keys() >= {"SPECULAR_TLC_TOOL_PYTHON", "SPECULAR_TLC_TOOL_SERVER"}


def test_concurrent_runs_get_the_union_of_their_servers(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    seen = tmp_path / "seen"
    seen.mkdir()
    # Each run records the servers it sees after both have started.
    _fake_cli(
        bin_dir,
        f"""
import time
sys.stdin.read()
open(os.path.join({str(seen)!r}, "started." + str(os.getpid())), "w").close()
deadline = time.time() + 20
while len([p for p in os.listdir({str(seen)!r}) if p.startswith("started.")]) < 2 and time.time() < deadline:
    time.sleep(0.05)
servers = sorted(json.load(open(".cursor/mcp.json"))["mcpServers"])
open(os.path.join({str(seen)!r}, "servers." + os.environ["SPECULAR_PHASE"]), "w").write(" ".join(servers))
time.sleep(0.5)
print(json.dumps({{"type": "result", "subtype": "success", "result": "ok", "session_id": "s" + str(os.getpid())}}))
""",
    )
    workspace = tmp_path / "ws"
    workspace.mkdir()
    runs = []
    for phase in ("main", "spec_validation"):
        env = _env(
            tmp_path,
            bin_dir,
            SPECULAR_PHASE=phase,
            SPECULAR_CONTEXT_MCP_JSON=_context_mcp_json(),
            SPECULAR_TLC_TOOL_JSON=_tlc_tool_json(tmp_path),
        )
        runs.append(
            subprocess.Popen(
                [str(ADAPTER_SH), "--prompt=x", f"--log={tmp_path / f'{phase}.log'}"],
                env=env,
                cwd=workspace,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
        )
    for run in runs:
        _, stderr = run.communicate(timeout=60)
        assert run.returncode == 0, stderr
    for phase in ("main", "spec_validation"):
        assert (seen / f"servers.{phase}").read_text() == "specular_context specular_tlc"
    assert list(workspace.iterdir()) == []


def test_invalid_tlc_tool_json_skips_registration(tmp_path: Path) -> None:
    bin_dir, capture = tmp_path / "bin", tmp_path / "capture.json"
    _recording_cli(bin_dir, capture)
    env = _env(tmp_path, bin_dir, SPECULAR_TLC_TOOL_JSON="{not json")
    assert _run(["--prompt=x", f"--log={tmp_path / 'p.log'}"], env, tmp_path).returncode == 0
    recorded = json.loads(capture.read_text())
    assert recorded["mcp"] is None


# ── Skills ──────────────────────────────────────────────────────────────────


def test_skill_refs_materialize_local_paths() -> None:
    for adapter in ("cursor-cli", str(ADAPTER_SH)):
        rendered = materialize_skill_refs(f"Use {prompt_skill_ids('code-analysis')}", adapter)
        assert "read the local Specular skill file at" in rendered
        assert rendered.endswith("SKILL.md`)")
