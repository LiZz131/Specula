"""Tests for scripts/infra/setup_cursor_mcp.py (Cursor CLI MCP registration)."""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
HELPER = REPO_ROOT / "scripts/infra/setup_cursor_mcp.py"
SETUP = REPO_ROOT / "scripts/infra/setup.sh"
WANTED = {"command": "/py", "args": ["/srv/mcp_server.py"], "env": {"SPECULAR_ROOT": "/specular"}}


def _register(config: Path, name: str = "tracedebugger") -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, "-I", str(HELPER), str(config), name, "/specular", "/py", "/srv/mcp_server.py"],
        capture_output=True,
        text=True,
        check=False,
    )


def test_adds_entry_to_a_new_config(tmp_path: Path) -> None:
    config = tmp_path / ".cursor/mcp.json"
    result = _register(config)
    assert result.returncode == 0 and "Cursor MCP configured: tracedebugger" in result.stdout
    assert json.loads(config.read_text()) == {"mcpServers": {"tracedebugger": WANTED}}


def test_keeps_other_servers_and_settings(tmp_path: Path) -> None:
    config = tmp_path / "mcp.json"
    config.write_text(json.dumps({"mcpServers": {"mine": {"url": "https://example.test"}}, "extra": True}))
    config.chmod(0o600)
    assert _register(config).returncode == 0
    payload = json.loads(config.read_text())
    assert payload == {"mcpServers": {"mine": {"url": "https://example.test"}, "tracedebugger": WANTED}, "extra": True}
    assert config.stat().st_mode & 0o777 == 0o600


def test_rerun_is_idempotent(tmp_path: Path) -> None:
    config = tmp_path / "mcp.json"
    assert _register(config).returncode == 0
    before = config.read_bytes()
    again = _register(config)
    assert again.returncode == 0 and "already configured" in again.stdout
    assert config.read_bytes() == before


def test_conflicting_invalid_and_symlinked_configs_are_left_unchanged(tmp_path: Path) -> None:
    conflicting = tmp_path / "conflict.json"
    conflicting.write_text(json.dumps({"mcpServers": {"tracedebugger": {"command": "other"}}}))
    invalid = tmp_path / "invalid.json"
    invalid.write_text("{not json")
    wrong_shape = tmp_path / "shape.json"
    wrong_shape.write_text(json.dumps({"mcpServers": []}))
    target = tmp_path / "real.json"
    target.write_text("{}")
    link = tmp_path / "link.json"
    link.symlink_to(target)
    for config in (conflicting, invalid, wrong_shape, link):
        before = config.read_bytes()
        result = _register(config)
        assert result.returncode == 3, (config, result.stdout)
        assert config.read_bytes() == before
    assert "differs from Specular's" in _register(conflicting).stdout
    assert "symbolic link" in _register(link).stdout


def test_usage_error() -> None:
    result = subprocess.run([sys.executable, "-I", str(HELPER)], capture_output=True, text=True, check=False)
    assert result.returncode == 2


def test_setup_registers_every_mcp_server_for_cursor() -> None:
    text = SETUP.read_text()
    assert 'command_exists cursor-agent && ask_yn "Register Specular MCP servers for Cursor CLI' in text
    block = text[text.index("command_exists cursor-agent") :]
    assert 'for entry in "${MCP_SERVERS[@]}"' in block.split("\nfi\n", 1)[0]
    assert '"$SCRIPT_DIR/setup_cursor_mcp.py"' in block and '"$HOME/.cursor/mcp.json"' in block
