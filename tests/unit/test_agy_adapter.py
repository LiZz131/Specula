"""Unit tests for the Google Antigravity CLI (agy) adapter."""

from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path

from specular.adapters.utils.event_stream import stream_events
from specular.adapters.utils.policy import POLICY_BLOCKED_RC
from specular.adapters.utils.transient import TRANSIENT_FAILURE_RC
from specular.adapters.utils.usage import UsageTotals
from specular.skill_refs import materialize_skill_refs, prompt_skill_ids

REPO_ROOT = Path(__file__).resolve().parents[2]
ADAPTER_SH = REPO_ROOT / "scripts/launch/adapters/agy.sh"


def _make_fake_agy(bin_dir: Path, script_body: str) -> Path:
    fake = bin_dir / "agy"
    fake.write_text(f"#!/usr/bin/env python3\n{script_body}\n", encoding="utf-8")
    fake.chmod(fake.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return fake


def test_agy_stream_events_and_usage(tmp_path: Path) -> None:
    lines = [
        json.dumps(
            {
                "event": "init",
                "conversation_id": "conv-123",
                "init": {"model": "gemini-4-neon-high", "cwd": "/tmp", "permission_mode": "always-proceed"},
            }
        ),
        json.dumps(
            {
                "event": "step_update",
                "step_update": {
                    "conversation_id": "conv-123",
                    "step_index": 1,
                    "state": "ACTIVE",
                    "step_type": "tool",
                    "tool_name": "run_command",
                    "tool_info": {"name": "run_command", "parameters": {"CommandLine": "echo hi"}},
                },
            }
        ),
        json.dumps(
            {
                "event": "step_update",
                "step_update": {
                    "conversation_id": "conv-123",
                    "step_index": 1,
                    "state": "DONE",
                    "step_type": "tool",
                    "tool_name": "run_command",
                    "tool_info": {"name": "run_command", "parameters": {"CommandLine": "echo hi"}, "output": "hi\n"},
                },
            }
        ),
        json.dumps(
            {
                "event": "step_update",
                "step_update": {
                    "conversation_id": "conv-123",
                    "step_index": 2,
                    "state": "DONE",
                    "step_type": "tool",
                    "tool_name": "run_command",
                    "tool_info": {
                        "name": "run_command",
                        "error": {"type": "ToolError", "message": "permission denied"},
                    },
                },
            }
        ),
        json.dumps(
            {
                "event": "step_update",
                "step_update": {
                    "conversation_id": "conv-123",
                    "step_index": 3,
                    "state": "ACTIVE",
                    "step_type": "agent_response",
                    "text_delta": "Hello ",
                },
            }
        ),
        json.dumps(
            {
                "event": "step_update",
                "step_update": {
                    "conversation_id": "conv-123",
                    "step_index": 3,
                    "state": "DONE",
                    "step_type": "agent_response",
                    "text_delta": "world!\n",
                    "usage": {
                        "input_tokens": 100,
                        "output_tokens": 25,
                        "thinking_tokens": 10,
                        "cache_read_tokens": 50,
                        "total_tokens": 125,
                    },
                },
            }
        ),
        json.dumps(
            {
                "event": "result",
                "result": {
                    "conversation_id": "conv-123",
                    "status": "SUCCESS",
                    "response": "Hello world!\n",
                    "num_turns": 2,
                    # Cumulative across turns; per-step usage above is what must be counted.
                    "usage": {
                        "input_tokens": 500,
                        "output_tokens": 90,
                        "thinking_tokens": 30,
                        "cache_read_tokens": 200,
                        "total_tokens": 590,
                    },
                },
            }
        ),
    ]
    activity = tmp_path / "activity.jsonl"
    log = tmp_path / "agent.log"
    status = stream_events("agy", activity, log, [(line + "\n").encode() for line in lines])
    assert status.successful_terminal is True
    assert status.session_id == "conv-123"
    assert status.terminal_error is None
    rendered = log.read_text(encoding="utf-8")
    assert "Hello world!" in rendered
    assert "run_command" in rendered
    assert "permission denied" in rendered
    assert status.usage["usage"] == {
        "input_tokens": 100,
        "cached_input_tokens": 50,
        "cache_write_input_tokens": 0,
        "output_tokens": 25,
        "reasoning_output_tokens": 10,
        "total_tokens": 175,
    }
    restored = UsageTotals.from_payload(status.usage)
    assert restored.as_usage() == status.usage["usage"]


def test_agy_missing_terminal_result_fails(tmp_path: Path) -> None:
    lines = [
        json.dumps({"event": "init", "conversation_id": "conv-truncated", "init": {"cwd": "/tmp"}}),
    ]
    status = stream_events("agy", tmp_path / "a.jsonl", tmp_path / "a.log", [(line + "\n").encode() for line in lines])
    assert status.successful_terminal is False
    assert status.terminal_error == "stream ended without an agy result event"


def test_agy_adapter_invocation_resume_and_system_prompt(tmp_path: Path) -> None:
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    target_dir = tmp_path / "target-repo"
    target_dir.mkdir()
    capture = tmp_path / "capture.json"
    _make_fake_agy(
        bin_dir,
        f"""
import json, sys
data = {{"argv": sys.argv[1:], "stdin": sys.stdin.read()}}
open({str(capture)!r}, "w", encoding="utf-8").write(json.dumps(data))
print(json.dumps({{"event": "init", "conversation_id": "conv-abc", "init": {{"cwd": "."}}}}))
print(json.dumps({{"event": "step_update", "step_update": {{"conversation_id": "conv-abc", "step_index": 1, "state": "DONE", "step_type": "agent_response", "text_delta": "DONE_OK\\n", "usage": {{"input_tokens": 10, "output_tokens": 2, "thinking_tokens": 0, "cache_read_tokens": 0, "total_tokens": 12}}}}}}))
print(json.dumps({{"event": "result", "result": {{"conversation_id": "conv-abc", "status": "SUCCESS", "response": "DONE_OK\\n", "num_turns": 1}}}}))
""",
    )
    rules_file = tmp_path / "rules.md"
    rules_file.write_text("NEVER SKIP CHECKS", encoding="utf-8")

    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
    env["AGY_MODEL"] = "gemini-4-neon-high"
    env["AGY_EFFORT"] = "high"
    env["SPECULAR_TARGET_REPO_DIR"] = str(target_dir)
    log_path = tmp_path / "phase.log"
    resume_state = tmp_path / "resume.json"

    first = subprocess.run(
        [
            str(ADAPTER_SH),
            "--prompt=Check invariant",
            f"--system-prompt-file={rules_file}",
            f"--log={log_path}",
            f"--resume-state={resume_state}",
        ],
        env=env,
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert first.returncode == 0, first.stderr
    recorded = json.loads(capture.read_text(encoding="utf-8"))
    assert "--input-format" in recorded["argv"]
    assert "--output-format" in recorded["argv"]
    assert "--dangerously-skip-permissions" in recorded["argv"]
    assert "--model" in recorded["argv"] and "gemini-4-neon-high" in recorded["argv"]
    assert "--effort" in recorded["argv"] and "high" in recorded["argv"]
    assert "--add-dir" in recorded["argv"] and str(target_dir.resolve()) in recorded["argv"]
    assert "--conversation" not in recorded["argv"]
    stdin_msg = json.loads(recorded["stdin"].strip())
    assert stdin_msg == {"event": "user", "message": {"content": "NEVER SKIP CHECKS\n\n---\n\nCheck invariant"}}
    assert "DONE_OK" in log_path.read_text(encoding="utf-8")

    # Second call with same resume_state passes --conversation conv-abc and does not duplicate rules.
    second = subprocess.run(
        [
            str(ADAPTER_SH),
            "--prompt=NEVER SKIP CHECKS\n\nContinue",
            f"--system-prompt-file={rules_file}",
            f"--log={log_path}",
            f"--resume-state={resume_state}",
        ],
        env=env,
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )
    assert second.returncode == 0, second.stderr
    recorded2 = json.loads(capture.read_text(encoding="utf-8"))
    idx = recorded2["argv"].index("--conversation")
    assert recorded2["argv"][idx + 1] == "conv-abc"
    stdin_msg2 = json.loads(recorded2["stdin"].strip())
    assert stdin_msg2["message"]["content"].count("NEVER SKIP CHECKS") == 1


def test_agy_error_exit_code_classification(tmp_path: Path) -> None:
    cases = (
        ("429 RESOURCE_EXHAUSTED quota exceeded", 75),
        ("Request blocked by content policy safety filter", POLICY_BLOCKED_RC),
        ("HTTP 503 service unavailable upstream timeout", TRANSIENT_FAILURE_RC),
    )
    for error_text, expected_rc in cases:
        bin_dir = tmp_path / f"bin-{expected_rc}"
        bin_dir.mkdir()
        _make_fake_agy(
            bin_dir,
            f"""
import json, sys
print(json.dumps({{"event": "result", "result": {{"conversation_id": "c1", "status": "ERROR", "error": {error_text!r}}}}}))
sys.exit(1)
""",
        )
        env = os.environ.copy()
        env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
        log_path = tmp_path / f"phase-{expected_rc}.log"
        res = subprocess.run(
            [str(ADAPTER_SH), "--prompt=hi", f"--log={log_path}"],
            env=env,
            cwd=tmp_path,
            capture_output=True,
            text=True,
            check=False,
        )
        assert res.returncode == expected_rc, f"{error_text}: got {res.returncode}, stderr={res.stderr}"


def test_agy_skill_refs_materialize_local_paths() -> None:
    rendered = materialize_skill_refs(f"Use {prompt_skill_ids('code-analysis')}", "agy")
    assert "read the local Specular skill file at" in rendered
    assert "SKILL.md" in rendered


def _run_fake_result(tmp_path: Path, name: str, result: dict[str, object]) -> subprocess.CompletedProcess[str]:
    bin_dir = tmp_path / f"bin-{name}"
    bin_dir.mkdir()
    _make_fake_agy(
        bin_dir,
        f"""
import json, sys
sys.stdin.read()
print(json.dumps({{"event": "init", "conversation_id": "c1"}}))
print(json.dumps({{"event": "result", "result": {{"conversation_id": "c1", **{result!r}}}}}))
""",
    )
    env = os.environ.copy()
    env["PATH"] = f"{bin_dir}:{env.get('PATH', '')}"
    return subprocess.run(
        [str(ADAPTER_SH), "--prompt=hi", f"--log={tmp_path / f'{name}.log'}"],
        env=env,
        cwd=tmp_path,
        capture_output=True,
        text=True,
        check=False,
    )


def test_agy_upstream_error_texts_are_classified(tmp_path: Path) -> None:
    # Verbatim result.error strings reported upstream (google-antigravity/antigravity-cli
    # #1018, #1518, #1517, #1446); agy has already retried these in-process.
    cases = (
        (
            "API error (attempt 3): RESOURCE_EXHAUSTED (code 429): Individual quota reached. "
            "Please upgrade your subscription to increase your limits. Resets in 2h39m52s.",
            75,
        ),
        ("API error (attempt 1): UNAVAILABLE (code 503): The service is currently unavailable.", TRANSIENT_FAILURE_RC),
        (
            'API error (attempt 1): request failed: Post "https://cloudcode-pa.googleapis.com/'
            'v1internal:streamGenerateContent?alt=sse": EOF',
            TRANSIENT_FAILURE_RC,
        ),
        ("The stream was interrupted. Please continue the task you were working on.", TRANSIENT_FAILURE_RC),
        ("failed to construct executor: unknown model key MODEL_PLACEHOLDER_M359: model not found", 1),
        ("authentication failed or timed out", 1),
    )
    for index, (error_text, expected_rc) in enumerate(cases):
        res = _run_fake_result(tmp_path, f"case{index}", {"status": "ERROR", "response": "", "error": error_text})
        assert res.returncode == expected_rc, f"{error_text}: got {res.returncode}, stderr={res.stderr}"


def test_agy_agent_response_text_is_not_a_provider_error(tmp_path: Path) -> None:
    res = _run_fake_result(
        tmp_path,
        "prose",
        {
            "status": "CANCELED",
            "response": "The replica returned HTTP 503 service unavailable after an upstream timeout.",
        },
    )
    assert res.returncode == 1, res.stderr
