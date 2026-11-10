"""Language-specific call graphs behind one interface.

``impact`` asks one question: *who calls this function?* Each language answers
it with its own tool. Backends share the :class:`Backend` interface; which
backend serves which language is configuration, not code.

* ``lsp``: any Language Server that implements the standard call hierarchy
  (``textDocument/prepareCallHierarchy`` + ``callHierarchy/incomingCalls``).
  The default servers are gopls (Go), rust-analyzer (Rust), jdtls (Java), and
  clangd (C/C++). Only the server command differs between languages.
* ``cflow``: GNU cflow's reverse call tree for C. It needs no build or
  compilation database.
* ``none``: no call graph.

Configuration (``--callgraph-config FILE``) overrides the defaults per language::

    {
        "languages": {"c": {"backend": "lsp", "server": "clangd"}},
        "servers": {"jdtls": {"command": ["/opt/jdtls/bin/jdtls", "-data", "{workspace}"]}},
    }
"""

from __future__ import annotations

import json
import os
import queue
import re
import shutil
import subprocess
import tempfile
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol

LANGUAGE_OF_SUFFIX = {
    "c": "c", "h": "c", "cc": "cpp", "cpp": "cpp", "cxx": "cpp", "hh": "cpp", "hpp": "cpp", "hxx": "cpp",
    "go": "go", "rs": "rust", "java": "java", "py": "python",
}  # fmt: skip

DEFAULT_LANGUAGES: dict[str, dict[str, str]] = {
    "c": {"backend": "cflow"},
    "cpp": {"backend": "lsp", "server": "clangd"},
    "go": {"backend": "lsp", "server": "gopls"},
    "rust": {"backend": "lsp", "server": "rust-analyzer"},
    "java": {"backend": "lsp", "server": "jdtls"},
}

DEFAULT_SERVERS: dict[str, dict[str, Any]] = {
    "gopls": {"command": ["gopls"], "language_id": "go"},
    "rust-analyzer": {"command": ["rust-analyzer"], "language_id": "rust"},
    "clangd": {"command": ["clangd", "--background-index"], "language_id": "c"},
    # Recent jdtls releases need a newer JDK than the project; point JAVA_HOME at it in the config:
    # {"servers": {"jdtls": {"env": {"JAVA_HOME": "/opt/jdk25"}}}}
    "jdtls": {"command": ["jdtls", "-data", "{workspace}"], "language_id": "java"},
}


@dataclass(frozen=True)
class Site:
    """A function definition: repository-relative path, name, and 1-based line of the name."""

    path: str
    function: str
    line: int


class Backend(Protocol):
    name: str

    def callers(self, site: Site) -> list[Site]:
        """Direct callers of the function defined at ``site``."""
        ...

    def close(self) -> None: ...


Log = Callable[[str], None]


def _quiet(_: str) -> None:
    return None


# ---------------------------------------------------------------------------
# cflow (C)


class CflowBackend:
    """Reverse call tree from GNU cflow, computed once for the whole tree."""

    name = "cflow"

    def __init__(self, root: Path, log: Log = _quiet) -> None:
        self.root = root
        self.log = log
        self._callers: dict[tuple[str, str], list[Site]] | None = None

    def _build(self) -> dict[tuple[str, str], list[Site]]:
        files = sorted(
            p.relative_to(self.root).as_posix()
            for p in self.root.rglob("*.c")
            if not any(part in {".git", "build", "tests", "test"} for part in p.relative_to(self.root).parts[:-1])
        )
        if shutil.which("cflow") is None:
            raise CallGraphError("cflow is not installed")
        # GNU format expands every symbol (POSIX format abbreviates repeats as back-references):
        #   callee() <type callee () at path:line>:
        #       caller() <type caller () at path:line>
        command = ["cflow", "--reverse", "--omit-arguments", "--depth=2", *files]
        result = subprocess.run(command, cwd=self.root, capture_output=True, text=True, timeout=600)
        self.log(f"cflow over {len(files)} files -> exit {result.returncode}, {len(result.stdout.splitlines())} lines")
        callers: dict[tuple[str, str], list[Site]] = {}
        current: tuple[str, str] | None = None
        entry = re.compile(r"^( *)(\w+)\(\)(?: <.* at ([^:>]+):(\d+)>)?:?\s*$")
        for line in result.stdout.splitlines():
            match = entry.match(line)
            if not match:
                continue
            level, function = len(match.group(1)) // 4, match.group(2)
            path, number = match.group(3) or "", int(match.group(4) or 0)
            if level == 0:
                current = (path, function)
                callers.setdefault(current, [])
            elif level == 1 and current is not None and path:
                callers[current].append(Site(path, function, number))
        return callers

    def callers(self, site: Site) -> list[Site]:
        if self._callers is None:
            self._callers = self._build()
        found = self._callers.get((site.path, site.function))
        if found is None:  # cflow keys static functions by file; others may be keyed by the first definition
            found = next((v for (p, f), v in self._callers.items() if f == site.function), [])
        return found

    def close(self) -> None:
        return None


# ---------------------------------------------------------------------------
# Language Server Protocol


class CallGraphError(RuntimeError):
    pass


class LspClient:
    """Minimal JSON-RPC client over stdio for one language server process."""

    def __init__(self, command: list[str], root: Path, env: dict[str, str], log: Log) -> None:
        self.log = log
        self.process = subprocess.Popen(
            command,
            cwd=root,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            env={**os.environ, **env},
        )
        self._next = 0
        self._responses: dict[int, queue.Queue[dict[str, Any]]] = {}
        self._lock = threading.Lock()
        self.progress: dict[str, str] = {}  # active work-done progress tokens -> title
        self.progress_seen = False
        self._reader = threading.Thread(target=self._read, daemon=True)
        self._reader.start()

    def _send(self, message: dict[str, Any]) -> None:
        body = json.dumps(message).encode()
        assert self.process.stdin is not None
        with self._lock:
            self.process.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
            self.process.stdin.flush()

    def _read(self) -> None:
        stream = self.process.stdout
        assert stream is not None
        while True:
            length = 0
            while True:
                header = stream.readline()
                if not header:
                    return
                if header in (b"\r\n", b"\n"):
                    break
                if header.lower().startswith(b"content-length:"):
                    length = int(header.split(b":")[1])
            message = json.loads(stream.read(length))
            if "id" in message and "method" in message:  # server -> client request
                self._answer(message)
            elif "id" in message:
                box = self._responses.get(message["id"])
                if box is not None:
                    box.put(message)
            elif message.get("method") == "$/progress":
                token, value = str(message["params"]["token"]), message["params"]["value"]
                if value.get("kind") == "begin":
                    self.progress[token] = value.get("title", "")
                    self.progress_seen = True
                elif value.get("kind") == "end":
                    self.progress.pop(token, None)
            elif message.get("method") == "language/status":  # jdtls
                if message["params"].get("type") == "ServiceReady":
                    self.progress_seen = True
                    self.progress.pop("jdtls", None)
                else:
                    self.progress.setdefault("jdtls", message["params"].get("message", ""))

    def _answer(self, message: dict[str, Any]) -> None:
        method = message["method"]
        if method == "workspace/configuration":
            result: Any = [None for _ in message["params"].get("items", [])]
        else:  # window/workDoneProgress/create, client/registerCapability, ...
            result = None
        self._send({"jsonrpc": "2.0", "id": message["id"], "result": result})

    def request(self, method: str, params: Any, timeout: float = 120) -> Any:
        self._next += 1
        ident = self._next
        box: queue.Queue[dict[str, Any]] = queue.Queue()
        self._responses[ident] = box
        self._send({"jsonrpc": "2.0", "id": ident, "method": method, "params": params})
        deadline = time.monotonic() + timeout
        try:
            while True:
                try:
                    message = box.get(timeout=1)
                    break
                except queue.Empty:
                    if self.process.poll() is not None:
                        raise CallGraphError(f"{method}: server exited with {self.process.returncode}") from None
                    if time.monotonic() > deadline:
                        raise CallGraphError(f"{method} timed out after {timeout}s") from None
        finally:
            self._responses.pop(ident, None)
        if "error" in message:
            raise CallGraphError(f"{method}: {message['error'].get('message')}")
        return message.get("result")

    def notify(self, method: str, params: Any) -> None:
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def close(self) -> None:
        try:
            self.request("shutdown", None, timeout=10)
            self.notify("exit", None)
        except (CallGraphError, OSError, ValueError):
            pass
        try:
            self.process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            self.process.kill()


class LspBackend:
    """Call hierarchy from a language server, queried on demand per function."""

    def __init__(
        self, root: Path, server: str, spec: dict[str, Any], log: Log = _quiet, ready_timeout: float = 900
    ) -> None:
        self.name = f"lsp:{server}"
        self.root = root.resolve()
        self.server = server
        self.spec = spec
        self.log = log
        self.ready_timeout = ready_timeout
        self._client: LspClient | None = None
        self._opened: set[str] = set()
        self._workspace: tempfile.TemporaryDirectory[str] | None = None

    def _start(self) -> LspClient:
        if self._client is not None:
            return self._client
        self._workspace = tempfile.TemporaryDirectory(prefix=f"specula-{self.server}-")
        command = [part.replace("{workspace}", self._workspace.name) for part in self.spec["command"]]
        if shutil.which(command[0]) is None and not Path(command[0]).is_file():
            raise CallGraphError(f"{self.server}: command not found: {command[0]}")
        started = time.monotonic()
        client = LspClient(command, self.root, dict(self.spec.get("env", {})), self.log)
        client.request(
            "initialize",
            {
                "processId": os.getpid(),
                "rootUri": self.root.as_uri(),
                "workspaceFolders": [{"uri": self.root.as_uri(), "name": self.root.name}],
                "capabilities": {
                    "window": {"workDoneProgress": True},
                    "textDocument": {"callHierarchy": {"dynamicRegistration": False}},
                    "workspace": {"configuration": True, "workspaceFolders": True},
                },
                "initializationOptions": self.spec.get("initialization_options", {}),
            },
            timeout=self.ready_timeout,
        )
        client.notify("initialized", {})
        self._client = client
        self._wait_ready(started)
        return client

    def _wait_ready(self, started: float) -> None:
        """Wait for indexing progress to finish (servers report it with $/progress)."""
        client = self._client
        assert client is not None
        quiet_since: float | None = None
        while time.monotonic() - started < self.ready_timeout:
            if client.process.poll() is not None:
                raise CallGraphError(f"{self.server} exited with {client.process.returncode}")
            if client.progress:
                quiet_since = None
            elif quiet_since is None:
                quiet_since = time.monotonic()
            elif time.monotonic() - quiet_since > (3 if client.progress_seen else 10):
                break
            time.sleep(0.5)
        self.log(
            f"{self.server} ready after {time.monotonic() - started:.0f}s"
            f"{' (still indexing: ' + ', '.join(client.progress.values()) + ')' if client.progress else ''}"
        )

    def _open(self, path: str) -> str:
        client = self._start()
        file = self.root / path
        uri = file.as_uri()
        if path not in self._opened:
            client.notify(
                "textDocument/didOpen",
                {
                    "textDocument": {
                        "uri": uri,
                        "languageId": self.spec.get("language_id", ""),
                        "version": 1,
                        "text": file.read_text(errors="replace"),
                    }
                },
            )
            self._opened.add(path)
        return uri

    def callers(self, site: Site) -> list[Site]:
        client = self._start()
        uri = self._open(site.path)
        text = (self.root / site.path).read_text(errors="replace").splitlines()
        line = text[site.line - 1] if 0 < site.line <= len(text) else ""
        column = max(line.find(site.function), 0)
        position = {"textDocument": {"uri": uri}, "position": {"line": site.line - 1, "character": column}}
        items: Any = None
        for attempt in range(4):  # servers may answer "content modified" while still indexing
            try:
                items = client.request("textDocument/prepareCallHierarchy", position)
                break
            except CallGraphError as exc:
                self.log(f"{self.server} prepareCallHierarchy {site.function}: {exc}; retry {attempt + 1}")
                time.sleep(2 * (attempt + 1))
        result: list[Site] = []
        for item in items or []:
            incoming = client.request("callHierarchy/incomingCalls", {"item": item}) or []
            for call in incoming:
                source = call["from"]
                path = self._relative(source["uri"])
                if path is None:
                    continue  # caller outside the repository (dependency)
                start = source.get("selectionRange", source["range"])["start"]["line"] + 1
                result.append(Site(path, _plain_name(source["name"]), start))
        return result

    def _relative(self, uri: str) -> str | None:
        path = Path(uri.removeprefix("file://"))
        try:
            return path.resolve().relative_to(self.root).as_posix()
        except ValueError:
            return None

    def close(self) -> None:
        if self._client is not None:
            self._client.close()
            self._client = None
        if self._workspace is not None:
            self._workspace.cleanup()
            self._workspace = None


def _plain_name(name: str) -> str:
    """Bare function name from server labels such as ``(*T).Method``, ``Type::method``, ``method(int)``."""
    name = name.split("(")[0] if not name.startswith("(") else name.split(")")[-1]
    return re.split(r"[.:]", name.strip(". "))[-1] or name


# ---------------------------------------------------------------------------
# Selection


class NoneBackend:
    name = "none"

    def callers(self, site: Site) -> list[Site]:
        return []

    def close(self) -> None:
        return None


class CallGraph:
    """Picks a backend per language, starts it lazily, and caches answers."""

    def __init__(self, root: Path, config: dict[str, Any] | None = None, log: Log = _quiet, mode: str = "auto") -> None:
        self.root = root.resolve()
        self.log = log
        self.mode = mode
        config = config or {}
        self.languages = {**DEFAULT_LANGUAGES, **config.get("languages", {})}
        self.servers = {
            **DEFAULT_SERVERS,
            **{k: {**DEFAULT_SERVERS.get(k, {}), **v} for k, v in config.get("servers", {}).items()},
        }
        self.ready_timeout = float(config.get("ready_timeout", 900))
        self._backends: dict[str, Backend] = {}
        self._failed: dict[str, str] = {}
        self._cache: dict[Site, list[Site]] = {}

    def backend_for(self, path: str) -> Backend | None:
        language = LANGUAGE_OF_SUFFIX.get(Path(path).suffix[1:])
        if self.mode == "none" or language is None:
            return None
        if language in self._failed:
            return None
        if language not in self._backends:
            choice = self.languages.get(language, {"backend": "none"})
            kind = choice.get("backend", "none")
            backend: Backend
            if kind == "cflow":
                backend = CflowBackend(self.root, self.log)
            elif kind == "lsp":
                server = choice["server"]
                backend = LspBackend(self.root, server, self.servers[server], self.log, self.ready_timeout)
            else:
                backend = NoneBackend()
            self.log(f"language {language} -> backend {backend.name}")
            self._backends[language] = backend
        return self._backends[language]

    def callers(self, site: Site) -> list[Site]:
        if site in self._cache:
            return self._cache[site]
        backend = self.backend_for(site.path)
        if backend is None:
            return []
        try:
            found = backend.callers(site)
        except (CallGraphError, OSError) as exc:
            language = LANGUAGE_OF_SUFFIX.get(Path(site.path).suffix[1:], "?")
            self._failed[language] = str(exc)
            self.log(f"backend {backend.name} failed for {language}: {exc}; no call graph for this language")
            backend.close()
            self._backends.pop(language, None)
            found = []
        unique = list(dict.fromkeys(found))
        self._cache[site] = unique
        return unique

    @property
    def failures(self) -> dict[str, str]:
        return dict(self._failed)

    def close(self) -> None:
        for backend in self._backends.values():
            backend.close()
        self._backends.clear()


def load_config(path: Path | None) -> dict[str, Any]:
    if path is None:
        return {}
    value = json.loads(path.read_text())
    if not isinstance(value, dict):
        raise CallGraphError(f"{path}: call-graph config must be a JSON object")
    return value
