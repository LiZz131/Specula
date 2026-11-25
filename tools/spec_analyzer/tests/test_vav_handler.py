"""VAV handler: a CLI run that fails before validation must not read as "no issues"."""

import asyncio
import json
import subprocess
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

from spec_mcp.handlers.vav_handler import VAVHandler  # noqa: E402
from spec_mcp.utils.errors import ExecutionError  # noqa: E402

FAILED = (
    "Processing input file: /work/spec/base.tla\nParsing TLA+ file with SANY...\n"
    "✅ SANY parsing successful!\nBuilding CFG with SANYCFGBuilder...\n"
    "ERROR: CFG building failed: Variable '\"1\"' in alias 'Order' is not defined in variables list\n"
)
PASSED = (
    "Running Variable Assignment Validation...\n\n=== Variable Assignment Validation Results ===\n"
    "No issues found. All variables are assigned exactly once in each branch.\n=== End of Validation Results ===\n"
)


@pytest.fixture
def handler(tmp_path, monkeypatch):
    spec = tmp_path / "base.tla"
    spec.write_text("---- MODULE base ----\n====\n")
    h = VAVHandler()
    monkeypatch.setattr(h, "_find_cfa_jar", lambda: "cfa.jar")
    monkeypatch.setattr(h, "_find_tla_jar", lambda: "tla2tools.jar")
    return h, str(spec)


def _run(monkeypatch, code, stdout, stderr=""):
    monkeypatch.setattr(subprocess, "run", lambda *a, **k: subprocess.CompletedProcess(a, code, stdout, stderr))


def test_cfg_failure_is_an_error(handler, monkeypatch):
    h, spec = handler
    _run(monkeypatch, 1, "", FAILED)
    with pytest.raises(ExecutionError, match="CFG building failed"):
        asyncio.run(h.execute({"spec_file": spec}))


def test_cfg_failure_reported_as_unsuccessful(handler, monkeypatch):
    h, spec = handler
    _run(monkeypatch, 1, "", FAILED)
    result = json.loads(asyncio.run(h.handle({"spec_file": spec})))
    assert result.get("success") is False


def test_missing_results_with_exit_zero_is_an_error(handler, monkeypatch):
    h, spec = handler
    _run(monkeypatch, 0, "Parsing TLA+ file with SANY...\n")
    with pytest.raises(ExecutionError, match="no validation results"):
        asyncio.run(h.execute({"spec_file": spec}))


def test_clean_run_reports_no_issues(handler, monkeypatch):
    h, spec = handler
    _run(monkeypatch, 0, PASSED)
    result = asyncio.run(h.execute({"spec_file": spec}))
    assert result["issue_count"] == 0
