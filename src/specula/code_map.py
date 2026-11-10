"""Code <-> model correspondence for persistent CI.

The map is one JSON file, ``spec/code-map.json``. The tool owns the extracted
part: model elements, their kinds, variable footprints, Trace events, and the
code anchors already written in the specification and instrumentation
documents. The Agent owns the ``agent`` part of each element and the
project-level ``code_state`` and ``out_of_scope`` lists. Re-extraction keeps the
Agent part of elements that still exist.

Commands:

* ``extract`` builds or refreshes the map and validates every anchor against
  the source tree.
* ``check`` reports what the Agent still has to classify.
* ``impact`` maps a source diff onto model elements. A changed hunk that maps
  to no element is reported, never dropped.

This is a heuristic, conservative aid. It never decides that a change is
irrelevant; it only orders what must be reviewed.
"""

from __future__ import annotations

import argparse
import fnmatch
import json
import re
import subprocess
import sys
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from specula.callgraph import CallGraph, CallGraphError, Site, load_config

VERSION = 1
FILENAME = "spec/code-map.json"

SOURCE_SUFFIXES = (
    "c", "h", "cc", "cpp", "cxx", "hh", "hpp", "hxx", "go", "rs", "java", "kt", "scala",
    "py", "ts", "js", "cs", "rb", "ex", "exs", "erl", "hs", "ml", "zig", "swift", "proto",
)  # fmt: skip
ANCHOR = re.compile(
    r"(?P<path>[A-Za-z0-9_][A-Za-z0-9_./-]*\.(?:" + "|".join(SOURCE_SUFFIXES) + r"))"
    r":(?P<start>\d+)(?:\s*-\s*(?P<end>\d+))?"
    r"(?:\s*\((?P<symbol>[A-Za-z_][A-Za-z0-9_:.]*)[^)]*\))?"
)
IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
DEFINITION = re.compile(r"^(?P<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?:\([^)]*\))?\s*==")
DECLARATION = re.compile(r"^(?P<kind>CONSTANTS?|VARIABLES?)\b(?P<rest>.*)$")
SECTION_BREAK = re.compile(r"^(?:-{4,}|={4,}|\\\*{4,}|\(\*{4,})")
SKIP_DIRS = {".git", "node_modules", "target", "build", "vendor", "third_party", ".specula-output", "dist"}

# Agent classifications for elements that have no direct code anchor.
STATUSES = {
    "mapped": "corresponds to the cited code",
    "environment": "fault, network, scheduler, or external-caller behavior anchored to an assumption or API",
    "model-glue": "modeling helper with no implementation counterpart",
    "check-parameter": "finite world size or exploration bound; no implementation counterpart",
    "requirement": "correctness requirement; cite its source (paper, doc, assertion, test)",
    "abstraction": "intentional abstraction of implementation state or steps; explain what it summarizes",
    "out-of-scope": "kept for structure but outside the modeled behavior; explain why",
}
REQUIRED_KINDS = {"constant", "variable", "init", "action", "property"}
NO_ANCHOR_STATUSES = set(STATUSES) - {"mapped"}


class CodeMapError(RuntimeError):
    """The map cannot be built or read."""


# Debug log: every classification and anchor decision with its file:line origin and rule.
DEBUG: list[str] | None = None
DEBUG_STREAM: Any = None  # open file when --debug-log is given, so long runs can be followed live


def _debug(stage: str, message: str) -> None:
    if DEBUG is not None:
        line = f"[{stage}] {message}"
        DEBUG.append(line)
        if DEBUG_STREAM is not None:
            DEBUG_STREAM.write(line + "\n")
            DEBUG_STREAM.flush()


# ---------------------------------------------------------------------------
# TLA+ structure


@dataclass
class Element:
    name: str
    kind: str  # constant | variable | init | action | property | helper | spec
    module: str
    line: int
    body: str = ""
    comments: list[tuple[int, str]] = field(default_factory=list)
    category: str | None = None
    reason: str = ""  # which rule assigned the kind, with its file:line evidence
    category_reason: str = ""


def _strip_comments(text: str) -> str:
    text = re.sub(r"\(\*.*?\*\)", " ", text, flags=re.S)
    return re.sub(r"\\\*.*", "", text)


def _comment(line: str) -> str | None:
    index = line.find("\\*")
    return line[index + 2 :].strip() if index >= 0 else None


def parse_module(path: Path) -> tuple[list[Element], list[tuple[int, str]]]:
    """Top-level declarations and definitions with their attached comments.

    A comment block directly above a definition or declaration (banner rules
    allowed, blank lines not) belongs to it. Indented and trailing comments
    belong to the enclosing definition. Other comment blocks are returned as
    floating comments so that code citations in them are not silently lost.
    """
    lines = path.read_text(errors="replace").splitlines()
    module = path.stem
    elements: list[Element] = []
    floating: list[tuple[int, str]] = []
    owner: Element | None = None
    pending: list[tuple[int, str]] = []
    gap = False
    declaring: str | None = None
    group_comments: list[tuple[int, str]] = []
    decl_open = False  # the declaration list continues: its last line ended with a comma
    in_block = False
    for number, raw in enumerate(lines, 1):
        stripped = raw.strip()
        comment_text: str | None = None
        if in_block or stripped.startswith("(*"):
            in_block = "*)" not in stripped
            comment_text = stripped.strip("()* ")
        elif stripped.startswith("\\*"):
            comment_text = stripped[2:].strip()
        if comment_text is not None:
            if SECTION_BREAK.match(stripped):
                # Banner rules frame a heading comment; they end a body but keep the heading.
                owner, declaring = None, None
            elif raw[:1].isspace() and owner is not None:
                owner.comments.append((number, comment_text))
            elif comment_text:
                if gap and pending:
                    floating.extend(pending)
                    pending = []
                gap = False
                owner = None if not raw[:1].isspace() else owner
                pending.append((number, comment_text))
            continue
        if not stripped:
            gap = bool(pending) or owner is not None
            if not decl_open:
                declaring = None
            continue
        if SECTION_BREAK.match(stripped) or stripped.startswith(("MODULE", "EXTENDS", "----")):
            floating.extend(pending)
            pending, gap, owner, declaring = [], False, None, None
            continue
        declaration = DECLARATION.match(raw)
        definition = DEFINITION.match(raw)
        if declaration:
            declaring = "constant" if declaration.group("kind").startswith("CONSTANT") else "variable"
            if gap:
                for at, note in pending:
                    _debug("parse", f"{module}.tla:{at} comment separated by a blank line -> floating: {note[:70]}")
                floating.extend(pending)
                pending = []
            group_comments, pending, gap, owner = pending, [], False, None
            _declare(elements, declaring, module, number, declaration.group("rest"), group_comments)
            decl_open = _strip_comments(declaration.group("rest")).rstrip().endswith(",")
            continue
        if declaring is not None and raw[:1].isspace() and not definition:
            if pending:  # a comment heading inside the list starts a sub-group
                group_comments, pending = pending, []
            gap = False
            _declare(elements, declaring, module, number, raw, group_comments)
            decl_open = _strip_comments(raw).rstrip().endswith(",")
            continue
        declaring, decl_open = None, False
        if definition:
            if gap:
                for at, note in pending:
                    _debug("parse", f"{module}.tla:{at} comment separated by a blank line -> floating: {note[:70]}")
                floating.extend(pending)
                pending = []
            owner = Element(definition.group("name"), "helper", module, number)
            owner.reason = f"top-level definition at {module}.tla:{number}; default kind helper"
            leading = f" with leading comments {pending[0][0]}-{pending[-1][0]}" if pending else ""
            _debug("parse", f"{module}.tla:{number} definition {owner.name}{leading}")
            owner.comments.extend(pending)
            pending, gap = [], False
            owner.body = raw.split("==", 1)[1]
            elements.append(owner)
            continue
        if owner is not None and not gap:
            owner.body += "\n" + raw
            text = _comment(raw)
            if text:
                owner.comments.append((number, text))
        elif owner is not None:
            # A blank line inside a definition body: keep accumulating.
            owner.body += "\n" + raw
            gap = False
            text = _comment(raw)
            if text:
                owner.comments.append((number, text))
    floating.extend(pending)
    return elements, floating


def _declare(
    elements: list[Element], kind: str, module: str, number: int, text: str, group: list[tuple[int, str]]
) -> None:
    code = _strip_comments(text)
    trailing = _comment(text)
    for name in IDENT.findall(code):
        if name in {"CONSTANT", "CONSTANTS", "VARIABLE", "VARIABLES"}:
            continue
        element = Element(name, kind, module, number)
        element.reason = f"declared in {kind.upper()}S at {module}.tla:{number}"
        group_text = f"; group comments {group[0][0]}-{group[-1][0]}" if group else ""
        _debug("parse", f"{module}.tla:{number} {kind} {name}{group_text}{'; trailing comment' if trailing else ''}")
        element.comments.extend(group)
        if trailing:
            element.comments.append((number, trailing))
        elements.append(element)


@dataclass
class Model:
    spec_dir: Path
    elements: dict[str, Element]
    cfg_properties: dict[str, list[str]]
    cfg_constants: dict[str, str]
    trace_events: dict[str, list[str]]
    floating: list[tuple[int, str]] = field(default_factory=list)


def _cfg_entries(path: Path) -> tuple[list[tuple[str, int]], dict[str, tuple[str, int]]]:
    properties: list[tuple[str, int]] = []
    constants: dict[str, tuple[str, int]] = {}
    section = None
    for number, raw in enumerate(path.read_text(errors="replace").splitlines(), 1):
        line = _strip_comments(raw).strip()
        if not line:
            continue
        head = line.split()[0]
        if head in {"INVARIANT", "INVARIANTS", "PROPERTY", "PROPERTIES", "CONSTANT", "CONSTANTS"}:
            section = "property" if head.startswith(("INVARIANT", "PROPERT")) else "constant"
            line = line[len(head) :].strip()
        elif head.isupper() and head.isalpha():
            section = None
            continue
        if section == "property":
            properties.extend((name, number) for name in IDENT.findall(line))
        elif section == "constant" and ("=" in line or "<-" in line):
            name, _, value = re.split(r"(=|<-)", line, maxsplit=1)
            constants[name.strip()] = (value.strip(), number)
    return properties, constants


def _constant_category(name: str, value: str | None) -> tuple[str | None, str]:
    if value is None:
        return None, "no value in any cfg"
    if value == name or re.fullmatch(r'"[^"]*"', value):
        return "enum", f"cfg value {value!r} is a model value standing for an implementation discriminator"
    if re.fullmatch(r"-?\d+", value):
        return "bound", f"cfg value {value} is a number (exploration bound)"
    if value.startswith("{") or ".." in value:
        return "world", f"cfg value {value} is a set or range (world size)"
    return None, f"cfg value {value!r} matches no category rule"


def load_model(spec_dir: Path) -> Model:
    base = spec_dir / "base.tla"
    if not base.is_file():
        raise CodeMapError(f"missing {base}")
    elements: dict[str, Element] = {}
    parsed, floating = parse_module(base)
    for element in parsed:
        if element.name in elements:
            _debug(
                "parse",
                f"base.tla:{element.line} duplicate name {element.name}; keeping base.tla:{elements[element.name].line}",
            )
        elements.setdefault(element.name, element)
    variables = {name for name, e in elements.items() if e.kind == "variable"}
    defs = {name: e for name, e in elements.items() if e.kind == "helper"}
    for name, element in defs.items():
        refs = _references(element.body)
        where = f"base.tla:{element.line}"
        if refs and refs <= variables | set(defs) and re.fullmatch(r"\s*<<[^>]*>>\s*", _strip_comments(element.body)):
            element.kind = "var-group"
            element.reason = (
                f"R-VARGROUP: {where} body is only a tuple of variables/groups <<{', '.join(sorted(refs))}>>"
            )
        elif name == "Init":
            element.kind = "init"
            element.reason = f"R-INIT: {where} is named Init"
        elif name in {"Spec", "Next"}:
            element.kind = "spec"
            element.reason = f"R-SPEC: {where} is named {name}"
    cfg_properties: dict[str, list[str]] = {}
    cfg_constants: dict[str, str] = {}
    constant_origin: dict[str, str] = {}
    for cfg in sorted(spec_dir.glob("*.cfg")):
        properties, constants = _cfg_entries(cfg)
        for prop, line in properties:
            cfg_properties.setdefault(prop, []).append(cfg.name)
            _debug("cfg", f"{cfg.name}:{line} enables property {prop}")
        for name, (value, line) in constants.items():
            if name not in cfg_constants:
                cfg_constants[name] = value
                constant_origin[name] = f"{cfg.name}:{line}"
    for name, why in _actions(elements, variables).items():
        elements[name].kind = "action"
        elements[name].reason = why
    for name in cfg_properties:
        if name in defs and elements[name].kind == "helper":
            elements[name].kind = "property"
            elements[
                name
            ].reason = f"R-PROPERTY: base.tla:{elements[name].line} named in INVARIANT/PROPERTY of {', '.join(cfg_properties[name])}"
    mc = spec_dir / "MC.tla"
    if mc.is_file():
        for element in parse_module(mc)[0]:
            if element.name in cfg_properties and element.name not in elements:
                element.kind = "property"
                element.reason = f"R-PROPERTY: MC.tla:{element.line} named in INVARIANT/PROPERTY of {', '.join(cfg_properties[element.name])}"
                elements[element.name] = element
    for name in cfg_properties:
        if name not in elements:
            _debug("cfg", f"property {name} is enabled in a cfg but defined in neither base.tla nor MC.tla; not mapped")
    for name, element in elements.items():
        if element.kind == "constant":
            element.category, why = _constant_category(name, cfg_constants.get(name))
            origin = constant_origin.get(name)
            element.category_reason = f"R-CONST: {origin + ' ' if origin else ''}{why}"
    for name, element in sorted(elements.items(), key=lambda item: (item[1].module, item[1].line)):
        if element.kind == "helper":
            element.reason += "; no other rule applied"
        _debug("classify", f"{name} -> {element.kind}: {element.reason}")
        if element.category_reason:
            _debug("classify", f"{name} -> category {element.category}: {element.category_reason}")
    return Model(spec_dir, elements, cfg_properties, cfg_constants, _trace_events(spec_dir, elements), floating)


def _references(body: str) -> set[str]:
    return set(IDENT.findall(_strip_comments(body)))


UNCHANGED = re.compile(r"UNCHANGED\s*(?:<<[^>]*>>|[A-Za-z_][A-Za-z0-9_]*)")


def _frame_free(body: str) -> str:
    """Body without UNCHANGED clauses, which neither read nor write a variable."""
    return UNCHANGED.sub(" ", _strip_comments(body))


def _primes(body: str, variables: set[str]) -> set[str]:
    """Variables assigned a new value: x' outside UNCHANGED, ignoring identity frames x' = x."""
    clean = _frame_free(body)
    written = set()
    for v in variables:
        name = re.escape(v)
        # Remove identity frames only; another branch may still assign the variable.
        rest = re.sub(rf"\b{name}'\s*=\s*{name}\b(?!\s*[\[(']|\s+EXCEPT)", " ", clean)
        if re.search(rf"\b{name}'", rest):
            written.add(v)
    return written


def _actions(elements: dict[str, Element], variables: set[str]) -> dict[str, str]:
    """Complete steps reachable from Next, with the reason each was chosen.

    A definition referenced from Next is an Action when it primes a variable or
    states UNCHANGED itself; otherwise it is treated as a disjunction of steps
    and expanded. Helpers such as Send, which only a step calls, stay helpers.
    """
    if "Next" not in elements:
        _debug("classify", "no Next definition in base.tla; no Actions")
        return {}
    next_line = elements["Next"].line
    seen: set[str] = set()
    stack = [(n, f"Next (base.tla:{next_line})") for n in _references(elements["Next"].body) if n in elements]
    result: dict[str, str] = {}
    while stack:
        name, via = stack.pop()
        if name in seen or elements[name].kind != "helper":
            continue
        seen.add(name)
        body = elements[name].body
        primed = sorted(_primes(body, variables))
        unchanged = "UNCHANGED" in _strip_comments(body)
        where = f"base.tla:{elements[name].line}"
        if primed or unchanged:
            evidence = f"primes {', '.join(primed)}" if primed else "states UNCHANGED"
            result[name] = f"R-ACTION: {where} referenced from {via} and {evidence} itself"
        else:
            _debug(
                "classify",
                f"{name} ({where}) referenced from {via} has no primes/UNCHANGED; expanding as a disjunction",
            )
            stack.extend((n, name) for n in _references(body) if n in elements and n != name)
    return dict(sorted(result.items(), key=lambda item: elements[item[0]].line))


def footprint(model: Model, name: str) -> tuple[set[str], set[str]]:
    """(read, written) variables, following helper definitions."""
    variables = {n for n, e in model.elements.items() if e.kind == "variable"}
    read: set[str] = set()
    written: set[str] = set()
    seen: set[str] = set()
    stack = [name]
    while stack:
        current = stack.pop()
        if current in seen:
            continue
        seen.add(current)
        body = model.elements[current].body
        refs = set(IDENT.findall(_frame_free(body)))
        read |= refs & variables
        written |= _primes(body, variables)
        stack.extend(r for r in refs if r in model.elements and model.elements[r].kind in {"helper", "var-group"})
    expanded = sorted(seen - {name})
    _debug(
        "footprint",
        f"{name}: reads {', '.join(sorted(read)) or '-'}; writes {', '.join(sorted(written)) or '-'}"
        f"{'; via ' + ', '.join(expanded) if expanded else ''} (UNCHANGED clauses and x' = x excluded)",
    )
    return read, written


def _trace_events(spec_dir: Path, elements: dict[str, Element]) -> dict[str, list[str]]:  # noqa: C901
    """Trace event names per Action, from the Trace.tla wrappers that call it."""
    trace = spec_dir / "Trace.tla"
    if not trace.is_file():
        return {}
    events: dict[str, list[str]] = {}
    actions = {n for n, e in elements.items() if e.kind == "action"}
    for wrapper in parse_module(trace)[0]:
        body = _strip_comments(wrapper.body)
        names = re.findall(r'Is\w*Event\(\s*"([A-Za-z_][A-Za-z0-9_]*)"', body) or re.findall(
            r'event\s*=\s*"([A-Za-z_][A-Za-z0-9_]*)"', body
        )
        called = _references(body) & actions
        for event in dict.fromkeys(names):
            targets = {event} if event in called else called
            rule = "event name equals the called Action" if event in called else "event mapped to every Action called"
            for action in sorted(targets):
                if event not in events.setdefault(action, []):
                    events[action].append(event)
                    _debug("trace", f"Trace.tla:{wrapper.line} {wrapper.name}: event {event!r} -> {action} ({rule})")
    return events


# ---------------------------------------------------------------------------
# Source tree


@dataclass
class Function:
    name: str
    start: int
    end: int


FUNCTION_PATTERNS: dict[str, re.Pattern[str]] = {
    "c": re.compile(r"^(?!\s)(?!(?:if|for|while|switch|return|else)\b)[A-Za-z_][\w\s\*,:<>&]*?\b(\w+)\s*\([^;]*$"),
    "go": re.compile(r"^func\s+(?:\([^)]*\)\s*)?(\w+)"),
    "rs": re.compile(
        r"^\s*(?:pub(?:\([^)]*\))?\s+)?(?:const\s+)?(?:async\s+)?(?:unsafe\s+)?(?:extern\s+\"C\"\s+)?fn\s+(\w+)"
    ),
    "java": re.compile(
        r"^\s+(?:(?:public|private|protected|static|final|synchronized|abstract|native|default|override)\s+)*"
        r"(?:<[^>]+>\s+)?[\w<>\[\], ?.]+\s+(\w+)\s*\([^;]*$"
    ),
    "py": re.compile(r"^\s*(?:async\s+)?def\s+(\w+)"),
}
LANGUAGE = {
    "c": "c", "h": "c", "cc": "c", "cpp": "c", "cxx": "c", "hh": "c", "hpp": "c", "hxx": "c",
    "go": "go", "rs": "rs", "java": "java", "kt": "java", "scala": "java", "cs": "java", "py": "py",
}  # fmt: skip
NOT_FUNCTIONS = {
    "if", "for", "while", "switch", "return", "sizeof", "catch", "new", "else", "synchronized", "try", "throw",
    "super", "this", "assert", "match", "loop", "defer", "go", "select", "with", "lock", "using", "foreach",
}  # fmt: skip


class SourceTree:
    def __init__(self, root: Path) -> None:
        self.root = root
        self._files: dict[str, list[str]] | None = None
        self._functions: dict[str, list[Function]] = {}
        self._lines: dict[str, list[str]] = {}

    def _index(self) -> dict[str, list[str]]:
        if self._files is None:
            files: dict[str, list[str]] = {}
            for path in self.root.rglob("*"):
                if any(part in SKIP_DIRS for part in path.relative_to(self.root).parts[:-1]):
                    continue
                if path.is_file() and path.suffix[1:] in SOURCE_SUFFIXES:
                    relative = path.relative_to(self.root).as_posix()
                    files.setdefault(path.name, []).append(relative)
            self._files = files
        return self._files

    def resolve(self, cited: str) -> list[str]:
        """Repository-relative paths matching a cited path or path suffix."""
        cited = cited.lstrip("./")
        if (self.root / cited).is_file():
            return [cited]
        candidates = self._index().get(Path(cited).name, [])
        return sorted(p for p in candidates if p == cited or p.endswith("/" + cited))

    def lines(self, relative: str) -> list[str]:
        if relative not in self._lines:
            self._lines[relative] = (self.root / relative).read_text(errors="replace").splitlines()
        return self._lines[relative]

    def functions(self, relative: str) -> list[Function]:
        if relative not in self._functions:
            self._functions[relative] = scan_functions(self.lines(relative), Path(relative).suffix[1:])
        return self._functions[relative]

    def enclosing(self, relative: str, line: int) -> Function | None:
        found = None
        for function in self.functions(relative):
            if function.start <= line <= function.end:
                found = function
        return found


def scan_functions(lines: list[str], suffix: str) -> list[Function]:
    """Approximate function ranges: a definition runs until the next one starts."""
    pattern = FUNCTION_PATTERNS.get(LANGUAGE.get(suffix, ""))
    if pattern is None:
        return []
    starts: list[tuple[int, str]] = []
    for number, line in enumerate(lines, 1):
        match = pattern.match(line)
        # Languages whose definitions start with a keyword (fn, func, def) need no blacklist: Rust's `fn new` is real.
        if not match or (LANGUAGE[suffix] in {"c", "java"} and match.group(1) in NOT_FUNCTIONS):
            continue
        if re.search(rf"\bnew\s+{re.escape(match.group(1))}\s*[(<]", line):
            continue  # Java/C# anonymous class or constructor call, not a definition
        if LANGUAGE[suffix] in {"c", "java"}:
            window = " ".join(lines[number - 1 : number + 6])
            brace, semicolon = window.find("{"), window.find(";")
            if brace < 0 or (0 <= semicolon < brace):
                continue
        starts.append((number, match.group(1)))
    result = []
    for index, (start, name) in enumerate(starts):
        end = starts[index + 1][0] - 1 if index + 1 < len(starts) else len(lines)
        result.append(Function(name, start, end))
    return result


# ---------------------------------------------------------------------------
# Anchors


def anchors_in(text: str) -> list[dict[str, Any]]:
    result = []
    for match in ANCHOR.finditer(text):
        start = int(match.group("start"))
        end = int(match.group("end") or start)
        anchor: dict[str, Any] = {"cited": match.group("path"), "lines": [start, max(start, end)]}
        if match.group("symbol"):
            anchor["symbol"] = match.group("symbol").split("::")[-1].split(".")[-1]
        result.append(anchor)
        # "file.go:603-647,711-726": each further range cites the same file.
        tail = text[match.end() :]
        position = 0
        while more := re.match(r"\s*,\s*(\d+)(?:\s*-\s*(\d+))?(?![\w.:/-])", tail[position:]):
            first = int(more.group(1))
            result.append({"cited": match.group("path"), "lines": [first, max(first, int(more.group(2) or first))]})
            position += more.end()
    return result


def _disambiguate(source: SourceTree, paths: list[str], end: int, hints: set[str]) -> tuple[str | None, str]:
    """Pick one of several files matching a bare cited name, or None.

    Rules, in order: keep candidates long enough for the cited lines; if one
    remains, take it. Otherwise prefer candidates in a directory that other
    citations in the same model name with a full path; take it if unique.
    """
    fitting = [p for p in paths if len(source.lines(p)) >= end]
    if len(fitting) == 1:
        return fitting[0], f"only {fitting[0]} among {len(paths)} candidates has line {end}"
    pool = fitting or paths
    hinted = [p for p in pool if str(Path(p).parent) in hints]
    if len(hinted) == 1:
        return hinted[0], f"only {hinted[0]} lies in a directory cited elsewhere with a full path"
    return None, ""


def resolve_anchor(source: SourceTree, anchor: dict[str, Any], hints: set[str] | None = None) -> list[str]:
    """Fill path/function fields; return problems (empty when the anchor is valid)."""
    problems = []
    paths = source.resolve(anchor["cited"])
    if not paths:
        return [f"{anchor['cited']}: file not found in source"]
    path = paths[0]
    if len(paths) > 1:
        chosen, rule = _disambiguate(source, paths, anchor["lines"][1], hints or set())
        if chosen is None:
            problems.append(f"{anchor['cited']}: ambiguous path ({', '.join(paths[:4])})")
        else:
            path = chosen
            anchor["resolved_by"] = rule
    anchor["path"] = path
    length = len(source.lines(path))
    start, end = anchor["lines"]
    if start < 1 or end > length:
        problems.append(f"{path}:{start}-{end}: outside the file ({length} lines)")
        return problems
    functions = {f.name for f in source.functions(path) if f.start <= end and start <= f.end}
    if functions:
        anchor["functions"] = sorted(functions)
        # A function-level anchor covers a function's start; a line anchor inside a body does not.
        covered = [f for f in source.functions(path) if start <= f.start <= end]
        anchor["covers"] = sorted({f.name for f in covered})
        anchor["covers_at"] = sorted(f.start for f in covered)  # distinguishes same-named functions in one file
    symbol = anchor.get("symbol")
    if symbol and functions and symbol not in functions:
        text = "\n".join(source.lines(path)[start - 1 : end])
        if not re.search(rf"\b{re.escape(symbol)}\b", text):
            problems.append(f"{path}:{start}-{end}: cites {symbol} but the range is in {', '.join(sorted(functions))}")
    return problems


def _markdown_rows(text: str) -> Iterable[tuple[int, str, list[str]]]:
    """Yield (line, heading, cells) for table rows and (line, heading, [text]) for other lines."""
    heading = ""
    for number, line in enumerate(text.splitlines(), 1):
        if line.startswith("#"):
            heading = line.lstrip("#").strip()
            yield number, heading, []
            continue
        if line.strip().startswith("|") and not re.fullmatch(r"\|[\s:|-]*\|?", line.strip()):
            yield number, heading, [cell.strip() for cell in line.strip().strip("|").split("|")]
        elif line.strip():
            yield number, heading, [line.strip()]


def _names_in(text: str, names: set[str]) -> list[str]:
    return [n for n in dict.fromkeys(IDENT.findall(text.replace("`", " "))) if n in names]


def instrumentation_anchors(
    spec_dir: Path, model: Model
) -> tuple[dict[str, list[dict[str, Any]]], dict[str, dict[str, str]]]:
    """Anchors per element and code projections per variable from the instrumentation documents."""
    actions = {n for n, e in model.elements.items() if e.kind == "action"}
    variables = {n for n, e in model.elements.items() if e.kind == "variable"}
    helpers = {n for n, e in model.elements.items() if e.kind == "helper"}
    found: dict[str, list[dict[str, Any]]] = {}
    projections: dict[str, str] = {}
    projection_origin: dict[str, str] = {}
    spec_md = spec_dir / "instrumentation-spec.md"
    if spec_md.is_file():
        section_action: str | None = None
        section_line = 0
        for number, heading, cells in _markdown_rows(spec_md.read_text(errors="replace")):
            if not cells:
                named = _names_in(heading, actions)
                section_action = named[0] if named else None
                section_line = number
                continue
            row = " | ".join(cells)
            row_actions = _names_in(cells[0], actions) if len(cells) > 1 else []
            target = row_actions[0] if row_actions else section_action
            rule = (
                "first table cell names the Action"
                if row_actions
                else f"inside section heading at line {section_line} naming the Action"
            )
            for anchor in anchors_in(row):
                if target:
                    anchor["origin"] = f"instrumentation-spec.md:{number}"
                    found.setdefault(target, []).append(anchor)
                    _debug(
                        "anchor",
                        f"instrumentation-spec.md:{number} -> {target} ({rule}): {anchor['cited']}:{anchor['lines'][0]}-{anchor['lines'][1]}",
                    )
                else:
                    _debug(
                        "anchor",
                        f"instrumentation-spec.md:{number} cites {anchor['cited']} but names no Action; ignored",
                    )
            if len(cells) > 1:
                model_names = [n for c in cells for n in _names_in(c, variables | helpers)]
                code = [c for c in cells if "(" in c and not _names_in(c, variables | helpers)]
                if model_names and code:
                    call = re.search(r"[A-Za-z_][\w.>-]*\([^)]*\)", code[0])
                    value = call.group(0) if call else code[0].strip("` ")
                    if model_names[0] not in projections:
                        projections[model_names[0]] = value
                        projection_origin[model_names[0]] = f"instrumentation-spec.md:{number}"
                        _debug("projection", f"instrumentation-spec.md:{number} table row: {model_names[0]} <- {value}")
    json_map = spec_dir / "instrumentation-map.json"
    if json_map.is_file():
        try:
            data = json.loads(json_map.read_text())
        except ValueError:
            data = {}
        for name, entry in data.items() if isinstance(data, dict) else []:
            if name in model.elements and isinstance(entry, dict) and isinstance(entry.get("source"), str):
                for anchor in anchors_in(entry["source"]):
                    anchor["origin"] = f"instrumentation-map.json:{name}.source"
                    found.setdefault(name, []).append(anchor)
                    _debug("anchor", f"instrumentation-map.json {name}.source -> {name}: {anchor['cited']}")
    return found, {name: {"code": value, "origin": projection_origin[name]} for name, value in projections.items()}


# ---------------------------------------------------------------------------
# Map construction


def _git_head(root: Path) -> str | None:
    result = subprocess.run(["git", "-C", str(root), "rev-parse", "HEAD"], capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else None


def _dedupe(anchors: list[dict[str, Any]]) -> list[dict[str, Any]]:
    seen: set[tuple[str, int, int, str]] = set()
    result = []
    for anchor in anchors:
        key = (anchor["cited"], anchor["lines"][0], anchor["lines"][1], anchor.get("origin", ""))
        if key not in seen:
            seen.add(key)
            result.append(anchor)
    return result


def extract(spec_dir: Path, source_root: Path, previous: dict[str, Any] | None = None) -> dict[str, Any]:
    model = load_model(spec_dir)
    source = SourceTree(source_root)
    documented, projections = instrumentation_anchors(spec_dir, model)
    issues: list[dict[str, str]] = []
    elements: dict[str, Any] = {}
    old = (previous or {}).get("elements", {})
    # Directories that the model cites with an unambiguous path disambiguate bare file names.
    hints: set[str] = set()
    cited = [a["cited"] for e in model.elements.values() for _, c in e.comments for a in anchors_in(c)]
    cited += [a["cited"] for found in documented.values() for a in found]
    for name in set(cited):
        paths = source.resolve(name)
        if len(paths) == 1:
            hints.add(str(Path(paths[0]).parent))
    _debug("resolve", f"{len(hints)} directories cited with unambiguous paths serve as disambiguation hints")
    for name, element in sorted(model.elements.items(), key=lambda item: (item[1].module, item[1].line)):
        anchors = []
        for line, comment in element.comments:
            for anchor in anchors_in(comment):
                anchor["origin"] = f"{element.module}.tla:{line}"
                _debug(
                    "anchor",
                    f"{element.module}.tla:{line} comment of {name}: {anchor['cited']}:{anchor['lines'][0]}-{anchor['lines'][1]}",
                )
                anchors.append(anchor)
        anchors.extend(documented.get(name, []))
        anchors = _dedupe(anchors)
        for anchor in anchors:
            problems = resolve_anchor(source, anchor, hints)
            for problem in problems:
                anchor["problem"] = problem
                issues.append({"element": name, "kind": "invalid-anchor", "detail": problem})
            if anchor.get("resolved_by") and not problems:
                issues.append(
                    {
                        "element": name,
                        "kind": "ambiguous-resolved",
                        "detail": f"{anchor['origin']} cites {anchor['cited']}; resolved to {anchor['path']}: {anchor['resolved_by']}",
                    }
                )
            _debug(
                "resolve",
                f"{name} [{anchor['origin']}] {anchor['cited']}:{anchor['lines'][0]}-{anchor['lines'][1]} -> "
                + (
                    f"INVALID: {'; '.join(problems)}"
                    if problems
                    else f"{anchor['path']} functions={anchor.get('functions', [])} covers={anchor.get('covers', [])}"
                    + (f" (disambiguated: {anchor['resolved_by']})" if anchor.get("resolved_by") else "")
                ),
            )
        entry: dict[str, Any] = {
            "kind": element.kind,
            "defined_at": f"{element.module}.tla:{element.line}",
            "reason": element.reason,
            "code": anchors,
        }
        if element.category:
            entry["category"] = element.category
        if element.category_reason:
            entry["category_reason"] = element.category_reason
        if element.kind in {"action", "init", "property", "helper"}:
            read, written = footprint(model, name)
            if element.kind == "init":
                entry["initializes"] = sorted(read)  # Init assigns with x = e, not primes
            elif element.kind == "property":
                entry["reads"] = sorted(read | written)  # x' in a temporal property is a next-state read
            else:
                entry["reads"] = sorted(read)
                if written:
                    entry["writes"] = sorted(written)
        if element.kind == "property":
            entry["enabled_in"] = model.cfg_properties.get(name, [])
        if name in model.trace_events:
            entry["trace_events"] = model.trace_events[name]
        if name in projections:
            entry["projection"] = projections[name]
        if name in old and isinstance(old[name], dict) and isinstance(old[name].get("agent"), dict):
            agent = old[name]["agent"]
            for anchor in agent.get("code", []):
                if not isinstance(anchor, dict) or not isinstance(anchor.get("path"), str):
                    issues.append(
                        {"element": name, "kind": "invalid-anchor", "detail": "agent.code entry needs a path"}
                    )
                    continue
                lines = anchor.get("lines")
                if not (isinstance(lines, list) and len(lines) == 2 and all(isinstance(n, int) for n in lines)):
                    issues.append(
                        {
                            "element": name,
                            "kind": "invalid-anchor",
                            "detail": f"{anchor['path']}: lines must be [start, end]",
                        }
                    )
                    continue
                anchor["cited"] = anchor["path"]
                for key in ("problem", "functions", "covers", "covers_at"):
                    anchor.pop(key, None)
                for problem in resolve_anchor(source, anchor):
                    anchor["problem"] = problem
                    issues.append({"element": name, "kind": "invalid-anchor", "detail": f"agent.code {problem}"})
            entry["agent"] = agent
        elements[name] = entry
    for line, comment in model.floating:
        for anchor in anchors_in(comment):
            _debug(
                "anchor",
                f"base.tla:{line} floating comment cites {anchor['cited']}:{anchor['lines'][0]} -> unattached-anchor issue",
            )
            detail = (
                f"base.tla:{line} cites {anchor['cited']}:{anchor['lines'][0]} outside any element: {comment[:100]}"
            )
            issues.append({"element": "", "kind": "unattached-anchor", "detail": detail})
    for name in sorted(set(old) - set(elements)):
        issues.append({"element": name, "kind": "removed-element", "detail": "no longer defined in base.tla"})
    result: dict[str, Any] = {
        "version": VERSION,
        "spec": "base.tla",
        "source_commit": _git_head(source_root),
        "elements": elements,
        "code_state": (previous or {}).get("code_state", []),
        "out_of_scope": (previous or {}).get("out_of_scope", []),
        "issues": issues,
    }
    return result


def read_map(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text())
    except (OSError, ValueError) as exc:
        raise CodeMapError(f"cannot read {path}: {exc}") from exc
    if not isinstance(data, dict) or data.get("version") != VERSION or not isinstance(data.get("elements"), dict):
        raise CodeMapError(f"{path}: not a version-{VERSION} code map")
    return data


def write_map(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


# ---------------------------------------------------------------------------
# Completeness


def _valid_code(entry: dict[str, Any]) -> list[dict[str, Any]]:
    raw = entry.get("agent")
    agent: dict[str, Any] = raw if isinstance(raw, dict) else {}
    code = list(entry.get("code", [])) + [a for a in agent.get("code", []) if isinstance(a, dict)]
    return [a for a in code if "problem" not in a and a.get("path")]


def check(data: dict[str, Any]) -> tuple[list[str], list[str]]:
    """(errors, warnings). Errors mean the map is not ready for CI use."""
    errors: list[str] = []
    warnings: list[str] = []
    for issue in data.get("issues", []):
        if issue.get("kind") == "invalid-anchor":
            errors.append(
                f"{issue['element'] or 'base.tla'}: {issue['detail']} (correct the citation, then extract again)"
            )
        elif issue.get("kind") == "unattached-anchor":
            warnings.append(f"{issue['detail']} (move it to the element it describes or record it in the map)")
        elif issue.get("kind") == "ambiguous-resolved":
            warnings.append(f"{issue['element']}: {issue['detail']} (write the full path to make it explicit)")
        elif issue.get("kind") == "removed-element":
            warnings.append(f"{issue['element']}: {issue['detail']}")
    for name, entry in data["elements"].items():
        raw = entry.get("agent")
        agent: dict[str, Any] = raw if isinstance(raw, dict) else {}
        status = agent.get("status")
        if status is not None and status not in STATUSES:
            errors.append(f"{name}: unknown agent.status {status!r}; use one of {', '.join(sorted(STATUSES))}")
            continue
        if status in NO_ANCHOR_STATUSES and not str(agent.get("note", "")).strip():
            errors.append(f"{name}: agent.status {status} requires a note")
        kind = entry.get("kind")
        has_code = bool(_valid_code(entry))
        if kind == "constant" and entry.get("category") in {"world", "bound"} and not status:
            continue  # cfg-only parameters are classified mechanically
        if kind in REQUIRED_KINDS and not has_code and status not in NO_ANCHOR_STATUSES:
            hint = "cite code" if kind != "property" else "cite its requirement source"
            errors.append(f"{name} ({kind}): no valid code anchor; {hint} or set agent.status with a note")
        elif kind == "helper" and not has_code and not status:
            warnings.append(f"{name} (helper): unclassified; mark mapped (with code) or model-glue")
    for index, item in enumerate(data.get("code_state", [])):
        if not isinstance(item, dict) or not item.get("code") or not item.get("affects"):
            errors.append(f"code_state[{index}]: requires code and affects")
            continue
        code = str(item["code"])
        if not _state_patterns(code):
            errors.append(f"code_state[{index}]: {code!r} names no field or flag that impact can match")
        prose = [w for w in re.findall(r"(?<![.\w>])[A-Za-z]+(?![\w(])", code) if "_" not in w and not w.endswith("_t")]
        if len(prose) > 1:
            warnings.append(
                f"code_state[{index}]: plain words {prose[:4]} in code; keep code names only, put explanations in note"
            )
    for index, item in enumerate(data.get("out_of_scope", [])):
        if not isinstance(item, dict) or not item.get("path") or not str(item.get("reason", "")).strip():
            errors.append(f"out_of_scope[{index}]: requires path and reason")
    return errors, warnings


# ---------------------------------------------------------------------------
# Impact of a source diff


@dataclass
class Hunk:
    old_path: str | None
    new_path: str | None
    old_start: int
    old_count: int
    new_start: int
    new_count: int
    context: str
    text: list[str] = field(default_factory=list)
    old_lines: list[int] = field(default_factory=list)  # deleted lines, or the insertion point
    new_lines: list[int] = field(default_factory=list)  # added lines

    @property
    def path(self) -> str:
        return self.new_path or self.old_path or "?"


def parse_diff(text: str) -> list[Hunk]:
    hunks: list[Hunk] = []
    cursor_old = cursor_new = 0
    old_path: str | None = None
    new_path: str | None = None
    for line in text.splitlines():
        if line.startswith("diff --git "):
            old_path = new_path = None
        elif line.startswith("--- "):
            old_path = None if line[4:].strip() == "/dev/null" else line[4:].strip().removeprefix("a/")
        elif line.startswith("+++ "):
            new_path = None if line[4:].strip() == "/dev/null" else line[4:].strip().removeprefix("b/")
        elif line.startswith("@@"):
            match = re.match(r"@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@ ?(.*)", line)
            if match:
                hunks.append(
                    Hunk(
                        old_path,
                        new_path,
                        int(match.group(1)),
                        int(match.group(2) if match.group(2) is not None else 1),
                        int(match.group(3)),
                        int(match.group(4) if match.group(4) is not None else 1),
                        match.group(5).strip(),
                    )
                )
            if match:
                cursor_old, cursor_new = hunks[-1].old_start, hunks[-1].new_start
        elif hunks and line[:1] in {"+", "-", " "}:
            hunk = hunks[-1]
            if line[:1] == " ":
                cursor_old += 1
                cursor_new += 1
                continue
            hunk.text.append(line)
            if line[:1] == "-":
                hunk.old_lines.append(cursor_old)
                cursor_old += 1
            else:
                hunk.new_lines.append(cursor_new)
                hunk.old_lines.append(max(cursor_old - 1, 1))  # insertion point on the old side
                cursor_new += 1
    return hunks


def _hunk_functions(hunk: Hunk, old: SourceTree | None, new: SourceTree | None) -> set[str]:
    names: set[str] = set()
    for tree, path, changed in ((old, hunk.old_path, hunk.old_lines), (new, hunk.new_path, hunk.new_lines)):
        if tree is None or path is None or not (tree.root / path).is_file():
            continue
        for line in changed:
            function = tree.enclosing(path, line)
            if function:
                names.add(function.name)
    if not names and hunk.context:
        match = re.search(r"(\w+)\s*\(", hunk.context)
        if match and match.group(1) not in NOT_FUNCTIONS:
            names.add(match.group(1))
    return names


def _added_functions(hunk: Hunk, suffix: str) -> set[str]:
    pattern = FUNCTION_PATTERNS.get(LANGUAGE.get(suffix, ""))
    if pattern is None:
        return set()
    added = {m.group(1) for line in hunk.text if line.startswith("+") and (m := pattern.match(line[1:]))}
    removed = {m.group(1) for line in hunk.text if line.startswith("-") and (m := pattern.match(line[1:]))}
    return added - removed - (NOT_FUNCTIONS if LANGUAGE.get(suffix) in {"c", "java"} else set())


def _state_patterns(code: str) -> list[tuple[str, re.Pattern[str]]]:
    """Patterns for the code names in a code_state entry.

    Names with an underscore (fields, flags, macros) match as whole words. A
    field without an underscore (``struct.flags``) matches only as member
    access, so ordinary words in changed lines do not trigger it. Type names
    ending in ``_t`` and prose are ignored.
    """
    patterns: list[tuple[str, re.Pattern[str]]] = []
    for match in re.finditer(r"(\.)?([A-Za-z_][A-Za-z0-9_]*)", code):
        token = match.group(2)
        if token.endswith("_t") or any(token == known for known, _ in patterns):
            continue
        if "_" in token.strip("_"):
            patterns.append((token, re.compile(rf"\b{re.escape(token)}\b")))
        elif match.group(1):
            patterns.append((token, re.compile(rf"(?:->|\.)\s*{re.escape(token)}\b")))
    return patterns


def _ranges(lines: list[int]) -> str:
    if not lines:
        return "-"
    values = sorted(set(lines))
    parts, start, prev = [], values[0], values[0]
    for value in values[1:] + [0]:
        if value != prev + 1:
            parts.append(f"{start}" if start == prev else f"{start}-{prev}")
            start = value
        prev = value
    return ",".join(parts)


TEST_PATH = re.compile(
    r"(^|/)(tests?|testing|testdata|__tests__|mocks?)/|_test\.(go|rs|py|c|cc|cpp)$|(^|/)test_[^/]*\.py$"
    r"|Tests?\.java$|(^|/)Test[^/]*\.java$|_mock\.go$|(^|/)mock_[^/]*$|(^|/)Mock[^/]*\.java$"
)


def _file_class(path: str) -> str:
    if Path(path).suffix[1:] not in SOURCE_SUFFIXES:
        return "non-source"
    if TEST_PATH.search(path):
        return "test"
    return "source"


def _definition(tree: SourceTree | None, path: str | None, name: str) -> Site | None:
    if tree is None or path is None or not (tree.root / path).is_file():
        return None
    for function in tree.functions(path):
        if function.name == name:
            return Site(path, name, function.start)
    return None


def _trace_callers(
    graph: CallGraph,
    starts: list[Site],
    mapped: dict[tuple[str, str], set[str]],
    scoped: Callable[[str, str], bool],
    depth: int,
    width: int,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Walk callers upward until a mapped function; return paths per reached element and a trace summary."""
    reached: dict[str, dict[str, Any]] = {}
    tops: set[str] = set()  # functions with no callers: entry points, tests, or callbacks
    frontier = [(site, [f"{site.function} ({site.path}:{site.line})"]) for site in starts]
    seen = {site for site in starts}
    for level in range(1, depth + 1):
        following: list[tuple[Site, list[str]]] = []
        for site, path in frontier:
            callers = graph.callers(site)
            if not callers:
                tops.add(f"{site.function} ({site.path})")
            _debug(
                "callgraph",
                f"level {level}: callers of {site.function} ({site.path}:{site.line}) -> "
                f"{[f'{c.function}@{c.path}:{c.line}' for c in callers] or '-'}",
            )
            skipped = [c for c in callers if _file_class(c.path) == "test"]
            if skipped:
                _debug("callgraph", f"  skip {len(skipped)} callers in test or mock files")
            for caller in callers:
                if _file_class(caller.path) == "test":
                    continue
                step = path + [f"{caller.function} ({caller.path}:{caller.line})"]
                if (caller.path, caller.function) in mapped:
                    for element in sorted(mapped[(caller.path, caller.function)]):
                        if element not in reached:
                            reached[element] = {"element": element, "via": caller.function, "path": step}
                            _debug("callgraph", f"  reached {element} through {' <- '.join(step)}")
                    continue  # a mapped function ends this branch
                if scoped(caller.path, caller.function):
                    _debug("callgraph", f"  stop at {caller.function}: declared out of scope")
                    continue
                if caller not in seen and len(following) < width:
                    seen.add(caller)
                    following.append((caller, step))
        frontier = following
        if not frontier:
            break
    if frontier:
        _debug("callgraph", f"  depth limit {depth} reached with {len(frontier)} unexplored callers")
    return list(reached.values()), {
        "explored": len(seen),
        "tops": sorted(tops)[:12],
        "depth_limited": bool(frontier),
    }


def impact(
    data: dict[str, Any],
    diff_text: str,
    old_root: Path | None = None,
    new_root: Path | None = None,
    graph: CallGraph | None = None,
    depth: int = 4,
    width: int = 60,
    old_graph: CallGraph | None = None,
) -> dict[str, Any]:
    """Map a diff onto model elements. ``graph`` serves the new tree; ``old_graph`` traces deleted functions."""
    old = SourceTree(old_root) if old_root else None
    new = SourceTree(new_root) if new_root else None
    elements: dict[str, dict[str, Any]] = data["elements"]
    by_path: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    # Functions are keyed by (file, name): languages such as Go and Java reuse names (Invoke, run) across files.
    by_function: dict[tuple[str, str], set[str]] = {}
    by_start: dict[tuple[str, int], set[str]] = {}  # (file, function start line in the old source)
    for name, entry in elements.items():
        for anchor in _valid_code(entry):
            by_path.setdefault(anchor["path"], []).append((name, anchor))
            for start in anchor.get("covers_at", []):
                by_start.setdefault((anchor["path"], start), set()).add(name)
            covered = anchor["covers"] if "covers" in anchor else anchor.get("functions", [])
            for function in covered + ([anchor["symbol"]] if anchor.get("symbol") else []):
                by_function.setdefault((anchor["path"], function), set()).add(name)
    projections = {
        name: IDENT.findall(
            str(
                entry["projection"].get("code", "") if isinstance(entry["projection"], dict) else entry["projection"]
            ).split("(")[0]
        )
        for name, entry in elements.items()
        if entry.get("projection")
    }

    def out_of_scope(path: str, functions: set[str] | str) -> dict[str, Any] | None:
        names = {functions} if isinstance(functions, str) else functions
        return next(
            (
                item
                for item in data.get("out_of_scope", [])
                if fnmatch.fnmatch(path, str(item.get("path", "")))
                and (not item.get("symbol") or item["symbol"] in names)
            ),
            None,
        )

    hunks: list[dict[str, Any]] = []
    direct: dict[str, list[str]] = {}
    via_callers: dict[str, list[dict[str, Any]]] = {}
    hidden: dict[str, list[str]] = {}
    hints: dict[str, list[str]] = {}
    for index, hunk in enumerate(parse_diff(diff_text), 1):
        file_class = _file_class(hunk.path)
        functions = _hunk_functions(hunk, old, new) if file_class != "non-source" else set()
        first = (hunk.new_lines or hunk.old_lines or [hunk.new_start])[0]
        location = f"{hunk.path}:{first}"
        label = f"{location} ({', '.join(sorted(functions)) or hunk.context or 'no function'})"
        _debug(
            "impact",
            f"H{index} {hunk.path} [{file_class}]: old changed lines {_ranges(hunk.old_lines)}, "
            f"new changed lines {_ranges(hunk.new_lines)}; enclosing functions {sorted(functions) or '-'}",
        )
        hits: dict[str, str] = {}
        state_hits: list[str] = []
        hint_hits: list[str] = []
        reached: list[dict[str, Any]] = []
        trace: dict[str, Any] = {}
        scope = None
        new_functions: set[str] = set()
        if file_class == "non-source":
            status = "non-source"
            _debug("impact", "  -> NON-SOURCE file (build, docs, config): listed separately; still needs a disposition")
        else:
            if hunk.old_path:
                for name, anchor in by_path.get(hunk.old_path, []):
                    start, stop = anchor["lines"]
                    if any(start <= line <= stop for line in hunk.old_lines):
                        hits.setdefault(name, f"lines overlap {anchor['path']}:{start}-{stop}")
            old_starts = {
                (f.name, f.start)
                for line in hunk.old_lines
                if old is not None and hunk.old_path and (old.root / hunk.old_path).is_file()
                for f in [old.enclosing(hunk.old_path, line)]
                if f is not None
            }
            for function, start in sorted(old_starts):
                for name in by_start.get((str(hunk.old_path), start), ()):
                    hits.setdefault(name, f"function {function} (old line {start})")
            precise = {function for function, _ in old_starts if by_start}
            for function in functions - precise:  # maps without start lines, or functions only in the new file
                for path in {hunk.old_path, hunk.new_path} - {None}:
                    for name in by_function.get((str(path), function), ()):
                        hits.setdefault(name, f"function {function}")
            changed = " ".join(line[1:] for line in hunk.text)
            for name, tokens in projections.items():
                if tokens and any(re.search(rf"\b{re.escape(t)}\b", changed) for t in tokens):
                    hint_hits.append(name)
                    hints.setdefault(name, []).append(f"{label} mentions projection {tokens[0]}")
            for item in data.get("code_state", []):
                matched = [t for t, pattern in _state_patterns(str(item.get("code", ""))) if pattern.search(changed)]
                if matched:
                    state_hits.append(str(item.get("code")))
                    for name in item.get("affects", []):
                        hidden.setdefault(name, []).append(f"{label} touches hidden state {', '.join(matched)}")
            scope = out_of_scope(hunk.path, functions)
            new_functions = _added_functions(hunk, Path(hunk.path).suffix[1:])
            if old is not None and hunk.old_path and (old.root / hunk.old_path).is_file():
                new_functions -= {f.name for f in old.functions(hunk.old_path)}  # changed signatures are not new
            for name, reason in hits.items():
                direct.setdefault(name, []).append(f"{label}: {reason}")
                _debug("impact", f"  -> {name} by {reason}")
            for state in state_hits:
                _debug("impact", f"  -> hidden state {state} named in changed lines")
            for name in hint_hits:
                _debug(
                    "impact", f"  -> hint only: changed text mentions the projection of {name} (not counted as a hit)"
                )
            if not hits and not state_hits and not scope and file_class == "source" and graph is not None:
                in_new = [s for n in sorted(functions) if (s := _definition(new, hunk.new_path, n)) is not None]
                in_old = [
                    s
                    for n in sorted(functions)
                    if all(x.function != n for x in in_new) and (s := _definition(old, hunk.old_path, n)) is not None
                ]
                for tree_graph, starts, side in ((graph, in_new, "new"), (old_graph, in_old, "old")):
                    if not starts or tree_graph is None:
                        continue
                    _debug(
                        "callgraph",
                        f"H{index}: tracing callers of {[s.function for s in starts]} in the {side} tree (depth {depth})",
                    )
                    found, summary = _trace_callers(
                        tree_graph, starts, by_function, lambda p, f: out_of_scope(p, f) is not None, depth, width
                    )
                    reached += found
                    trace = {
                        "explored": trace.get("explored", 0) + summary["explored"],
                        "tops": sorted(set(trace.get("tops", [])) | set(summary["tops"]))[:12],
                        "depth_limited": trace.get("depth_limited", False) or summary["depth_limited"],
                    }
                    for item in reached:
                        via_callers.setdefault(item["element"], []).append({"hunk": label, "path": item["path"]})
            if hits or state_hits:
                status = "mapped"
            elif scope:
                status = "declared-out-of-scope"
                _debug("impact", f"  -> declared out of scope: {scope.get('reason')}")
            elif reached:
                status = "reached-via-callers"
            elif file_class == "test":
                status = "test"
                _debug("impact", "  -> TEST file with no anchor: listed separately; still needs a disposition")
            else:
                status = "unmapped"
                _debug("impact", "  -> UNMAPPED: no anchor, function, code_state, or caller path matched")
            if new_functions:
                _debug(
                    "impact",
                    f"  -> new functions {sorted(new_functions)} (defined in + lines, absent from the old file)",
                )
        hunks.append(
            {
                "id": f"H{index}",
                "location": location,
                "file_class": file_class,
                "functions": sorted(functions),
                "status": status,
                "elements": sorted(hits),
                "reached": [{"element": r["element"], "path": r["path"]} for r in reached],
                "caller_trace": trace or None,
                "hidden_state": state_hits,
                "projection_hints": sorted(hint_hits),
                "out_of_scope_reason": scope.get("reason") if scope else None,
                "new_functions": sorted(new_functions),
            }
        )
    written: set[str] = set()
    for name in direct:
        written |= set(elements[name].get("writes", []))
        if elements[name].get("kind") == "variable":
            written.add(name)
    readers: dict[str, dict[str, list[str]]] = {}
    for variable in sorted(written):
        users = [
            n
            for n, e in elements.items()
            if n not in direct and e.get("kind") in {"action", "property"} and variable in e.get("reads", [])
        ]
        readers[variable] = {
            "actions": sorted(n for n in users if elements[n]["kind"] == "action"),
            "properties": sorted(n for n in users if elements[n]["kind"] == "property"),
        }
    statuses = ["mapped", "reached-via-callers", "declared-out-of-scope", "unmapped", "test", "non-source"]
    return {
        "version": VERSION,
        "map_source_commit": data.get("source_commit"),
        "direct": {name: direct[name] for name in sorted(direct)},
        "via_callers": {name: via_callers[name] for name in sorted(via_callers)},
        "hidden_state": hidden,
        "projection_hints": hints,
        "propagated": readers,
        "hunks": hunks,
        "callgraph": {"failures": graph.failures} if graph is not None else None,
        "summary": {
            "hunks": len(hunks),
            **{key.replace("-", "_"): sum(h["status"] == key for h in hunks) for key in statuses},
            "new_functions": sorted({f for h in hunks for f in h["new_functions"]}),
        },
    }


def _group_by_file(hunks: list[dict[str, Any]]) -> list[str]:
    grouped: dict[str, dict[str, int]] = {}
    for h in hunks:
        file = h["location"].rsplit(":", 1)[0]
        for function in h["functions"] or ["(no function)"]:
            grouped.setdefault(file, {}).setdefault(function, 0)
            grouped[file][function] += 1
    lines = []
    for file, functions in sorted(grouped.items()):
        parts = ", ".join(f"{f}" + (f" ×{n}" if n > 1 else "") for f, n in sorted(functions.items()))
        lines.append(f"- `{file}`: {parts}")
    return lines


def render_impact(report: dict[str, Any]) -> str:
    s = report["summary"]
    out = [
        "# Code-map impact",
        "",
        f"Map source commit: `{report.get('map_source_commit') or 'unknown'}`. Hunks: {s['hunks']}: "
        f"mapped {s['mapped']}, reached via callers {s['reached_via_callers']}, declared out of scope "
        f"{s['declared_out_of_scope']}, **unmapped {s['unmapped']}**, test {s['test']}, non-source {s['non_source']}.",
        "",
        "This report orders review; it never proves a change irrelevant. Read the complete diff. "
        "Hunk ids (H1, H2, ...) are the keys of `update-scope.json`.",
        "",
        "## Directly affected model elements",
        "",
        "Each of these must appear in the Chapter 1 projection with an explicit conclusion.",
        "",
    ]
    out += [f"- **{name}**: " + "; ".join(reasons) for name, reasons in report["direct"].items()] or ["- none"]
    out += [
        "",
        "## Reached through callers",
        "",
        "Changed functions with no anchor whose callers lead to a mapped function. Decide whether the change reaches "
        "the element's modeled behavior through that call path.",
        "",
    ]
    via = report.get("via_callers", {})
    out += [
        f"- **{name}**: " + "; ".join(f"{p['hunk']}: {' <- '.join(p['path'])}" for p in paths)
        for name, paths in via.items()
    ] or ["- none"]
    out += ["", "## Hidden implementation state", ""]
    out += [f"- **{name}**: " + "; ".join(reasons) for name, reasons in report["hidden_state"].items()] or ["- none"]
    out += [
        "",
        "## Readers of variables written by the affected elements",
        "",
        "Interaction candidates (unchanged Actions that read updated state) and properties to recheck.",
        "",
    ]
    for variable, users in report["propagated"].items():
        out.append(
            f"- `{variable}`: actions {', '.join(users['actions']) or 'none'}; "
            f"properties {', '.join(users['properties']) or 'none'}"
        )
    if not report["propagated"]:
        out.append("- none")
    by_status = {
        key: [h for h in report["hunks"] if h["status"] == key]
        for key in ("unmapped", "declared-out-of-scope", "test", "non-source")
    }
    out += [
        "",
        "## Unmapped hunks",
        "",
        "No anchor, code_state entry, or caller path reaches the model. Do not skip them: decide whether each changes "
        "modeled behavior, is outside the modeling scope (record it in out_of_scope), or reveals a missing map entry.",
        "",
    ]

    def traced(h: dict[str, Any]) -> str:
        t = h.get("caller_trace")
        if not t:
            return ""
        limit = "; depth limit reached" if t["depth_limited"] else ""
        return f" — callers traced ({t['explored']} functions{limit}); topmost: {', '.join(t['tops']) or '-'}"

    out += [
        f"- {h['id']} {h['location']} ({', '.join(h['functions']) or 'no function'}){traced(h)}"
        for h in by_status["unmapped"]
    ][:40] or ["- none"]
    if len(by_status["unmapped"]) > 40:
        out += ["", f"{len(by_status['unmapped'])} unmapped hunks; grouped by file:", ""] + _group_by_file(
            by_status["unmapped"]
        )
    if by_status["declared-out-of-scope"]:
        out += ["", "## Declared out of scope", "", "Confirm the recorded reason still holds.", ""]
        out += [f"- {h['id']} {h['location']}: {h['out_of_scope_reason']}" for h in by_status["declared-out-of-scope"]][
            :40
        ]
    if by_status["test"]:
        out += [
            "",
            "## Test code",
            "",
            "Tests can reveal the intended behavior of an update; they rarely change it.",
            "",
        ]
        out += _group_by_file(by_status["test"])
    if by_status["non-source"]:
        out += ["", "## Non-source files", "", "Build, documentation, or configuration changes.", ""]
        out += [f"- {h['id']} {h['location']}" for h in by_status["non-source"]]
    if report.get("projection_hints"):
        out += [
            "",
            "## Projection hints",
            "",
            "Changed text mentions the getter a trace uses for these elements. "
            "Usually a log or read; not counted as a hit.",
            "",
        ]
        out += [f"- **{name}**: " + "; ".join(r) for name, r in report["projection_hints"].items()]
    if s["new_functions"]:
        out += [
            "",
            "## New functions",
            "",
            "A new entry point, message handler, timer, or callback can require a new Action or environment step.",
            "",
            "- " + ", ".join(s["new_functions"]),
        ]
    if report.get("callgraph") and report["callgraph"]["failures"]:
        out += ["", "## Call graph unavailable", ""]
        out += [f"- {lang}: {why}" for lang, why in report["callgraph"]["failures"].items()]
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# CLI


# ---------------------------------------------------------------------------
# Stage 2: update scope (projection and disposition)

SCOPE_FILE = "spec/update-scope.json"
HUNK_DISPOSITIONS = {
    "reaches-model": "the change alters behavior of the listed model elements (via)",
    "no-behavior-change": "no modeled behavior changes (logging, refactor, comments); evidence required",
    "out-of-scope": "outside the modeling scope; a matching out_of_scope entry must exist in code-map.json",
    "map-gap": "modeled code the map missed; a valid anchor for this code must now exist in code-map.json",
    "non-model-file": "test, build, documentation, or configuration change that does not alter implementation behavior",
}
ELEMENT_VERDICTS = {
    "changed": "the element's modeled behavior must change",
    "now-wrong": "the existing model was already wrong here; repair needed regardless of the update",
    "unchanged": "reviewed; modeled behavior is the same (evidence required)",
}
ENTRY_VERDICTS = {"new-action", "new-environment-step", "internal"}


def scope_skeleton(report: dict[str, Any], data: dict[str, Any], previous: dict[str, Any] | None) -> dict[str, Any]:
    """Fill-in skeleton for update-scope.json from an impact report; keeps earlier Agent answers."""
    old_hunks = {h["location"]: h for h in (previous or {}).get("hunks", [])}
    old_elements = {e["name"]: e for e in (previous or {}).get("elements", [])}
    hunks = []
    for h in report["hunks"]:
        entry = {
            "id": h["id"],
            "location": h["location"],
            "functions": h["functions"],
            "impact_status": h["status"],
            "impact_elements": h["elements"] + [r["element"] for r in h.get("reached", [])],
            "disposition": None,
            "via": [],
            "evidence": "",
        }
        for key in ("disposition", "via", "evidence"):
            if h["location"] in old_hunks and old_hunks[h["location"]].get(key):
                entry[key] = old_hunks[h["location"]][key]
        hunks.append(entry)
    sources: dict[str, set[str]] = {}
    for name in report["direct"]:
        sources.setdefault(name, set()).add("direct")
    for name in report.get("via_callers", {}):
        sources.setdefault(name, set()).add("callers")
    for name in report["hidden_state"]:
        sources.setdefault(name, set()).add("hidden-state")
    elements = []
    for name in sorted(sources):
        entry = {
            "name": name,
            "kind": data["elements"].get(name, {}).get("kind"),
            "sources": sorted(sources[name]),
            "verdict": None,
            "evidence": "",
        }
        if name in old_elements:
            entry["verdict"] = old_elements[name].get("verdict")
            entry["evidence"] = old_elements[name].get("evidence", "")
        elements.append(entry)
    actions = sorted({a for users in report["propagated"].values() for a in users["actions"]})
    properties = sorted({p for users in report["propagated"].values() for p in users["properties"]})
    old_interaction = (previous or {}).get("interaction", {})
    old_properties = (previous or {}).get("properties", {})
    return {
        "version": VERSION,
        "map_source_commit": report.get("map_source_commit"),
        "hunks": hunks,
        "elements": elements,
        "new_functions": [
            {"function": f, "verdict": None, "evidence": ""}
            | next((o for o in (previous or {}).get("new_functions", []) if o.get("function") == f), {})
            for f in report["summary"]["new_functions"]
        ],
        "interaction": {
            "candidates": actions,
            "selected": old_interaction.get("selected", {}),
            "rejected": old_interaction.get("rejected", {}),
        },
        "properties": {
            "candidates": properties,
            "recheck": old_properties.get("recheck", {}),
            "skip": old_properties.get("skip", {}),
        },
        "derived": None,
    }


def _anchor_covers(data: dict[str, Any], path: str, functions: list[str]) -> list[str]:
    names = []
    for name, entry in data["elements"].items():
        for anchor in _valid_code(entry):
            covered = set(anchor.get("covers", [])) | set(anchor.get("functions", []))
            if anchor.get("path") == path and (covered & set(functions) or not functions):
                names.append(name)
    return sorted(set(names))


def scope_check(scope: dict[str, Any], data: dict[str, Any]) -> tuple[list[str], list[str], dict[str, Any]]:
    """Validate an update scope against the current map; return (errors, warnings, derived)."""
    errors: list[str] = []
    warnings: list[str] = []
    elements = data["elements"]
    verdicts = {e["name"]: e for e in scope.get("elements", [])}
    for h in scope.get("hunks", []):
        hid = f"{h['id']} {h['location']}"
        disposition = h.get("disposition")
        path = h["location"].rsplit(":", 1)[0]
        if disposition not in HUNK_DISPOSITIONS:
            errors.append(f"{hid}: disposition must be one of {', '.join(HUNK_DISPOSITIONS)}")
            continue
        if not str(h.get("evidence", "")).strip():
            errors.append(f"{hid}: {disposition} needs evidence")
        _debug("scope", f"{hid}: {disposition} via {h.get('via') or '-'} (impact said {h['impact_status']})")
        if disposition == "reaches-model":
            if not h.get("via"):
                errors.append(f"{hid}: reaches-model must name the model elements it reaches in via")
            for name in h.get("via", []):
                if name not in elements:
                    errors.append(f"{hid}: via names unknown element {name}")
                elif name not in verdicts:
                    errors.append(f"{hid}: {name} is reached but has no entry in elements; add it with a verdict")
        elif disposition == "out-of-scope":
            if not any(
                fnmatch.fnmatch(path, str(item.get("path", "")))
                and (not item.get("symbol") or item["symbol"] in h.get("functions", []))
                for item in data.get("out_of_scope", [])
            ):
                errors.append(
                    f"{hid}: out-of-scope but code-map.json has no matching out_of_scope entry; record it there"
                )
        elif disposition == "map-gap":
            covered = _anchor_covers(data, path, h.get("functions", []))
            if not covered:
                errors.append(
                    f"{hid}: map-gap but no valid anchor covers {path} {h.get('functions')}; add it, then extract"
                )
            else:
                _debug("scope", f"  map-gap now covered by {covered}")
        elif disposition == "no-behavior-change" and h.get("impact_elements"):
            warnings.append(
                f"{hid}: impact linked it to {h.get('impact_elements')} but it is marked no-behavior-change; "
                "make sure the evidence covers those elements"
            )
        elif disposition == "non-model-file" and h["impact_status"] not in {"test", "non-source"}:
            warnings.append(f"{hid}: non-model-file used for a {h['impact_status']} hunk")
    for name, e in verdicts.items():
        if e.get("verdict") not in ELEMENT_VERDICTS:
            errors.append(f"element {name}: verdict must be one of {', '.join(ELEMENT_VERDICTS)}")
        elif not str(e.get("evidence", "")).strip():
            errors.append(f"element {name}: verdict {e['verdict']} needs evidence")
        if name not in elements:
            errors.append(f"element {name}: not in code-map.json")
    for f in scope.get("new_functions", []):
        if f.get("verdict") not in ENTRY_VERDICTS or not str(f.get("evidence", "")).strip():
            errors.append(
                f"new function {f.get('function')}: verdict ({', '.join(sorted(ENTRY_VERDICTS))}) and evidence required"
            )
    for group, accept, reject in (("interaction", "selected", "rejected"), ("properties", "recheck", "skip")):
        block = scope.get(group, {})
        decided = set(block.get(accept, {})) | set(block.get(reject, {}))
        for name in block.get("candidates", []):
            if name not in decided:
                errors.append(f"{group} candidate {name}: put it in {accept} or {reject} with a reason")
        for name, reason in {**block.get(accept, {}), **block.get(reject, {})}.items():
            if not str(reason).strip():
                errors.append(f"{group} {name}: reason required")
    changed = sorted(n for n, e in verdicts.items() if e.get("verdict") in {"changed", "now-wrong"})
    new_steps = sorted(
        f["function"]
        for f in scope.get("new_functions", [])
        if f.get("verdict") in {"new-action", "new-environment-step"}
    )
    affected_actions = sorted(n for n in changed if elements.get(n, {}).get("kind") == "action")
    required = bool(changed or new_steps)
    derived = {
        "disposition": "MODEL_CHANGE_REQUIRED" if required else "NO_MODEL_CHANGE",
        "changed_elements": changed,
        "affected_actions": affected_actions,
        "new_steps": new_steps,
        "interaction_actions": sorted(scope.get("interaction", {}).get("selected", {})),
        "properties_to_recheck": sorted(scope.get("properties", {}).get("recheck", {})),
        "repairs": sorted(n for n, e in verdicts.items() if e.get("verdict") == "now-wrong"),
        "hunk_counts": {d: sum(h.get("disposition") == d for h in scope.get("hunks", [])) for d in HUNK_DISPOSITIONS},
    }
    _debug(
        "scope", f"derived disposition {derived['disposition']}: changed {changed or '-'}; new steps {new_steps or '-'}"
    )
    return errors, warnings, derived


def _summary(data: dict[str, Any]) -> str:
    kinds: dict[str, list[int]] = {}
    for entry in data["elements"].values():
        counts = kinds.setdefault(entry["kind"], [0, 0])
        counts[0] += 1
        counts[1] += bool(_valid_code(entry))
    parts = [f"{kind} {anchored}/{total}" for kind, (total, anchored) in sorted(kinds.items())]
    return f"anchored elements: {', '.join(parts)}; invalid anchors: " + str(
        sum(i["kind"] == "invalid-anchor" for i in data.get("issues", []))
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="specula code-map", description="Build and use the code <-> model map.")
    sub = parser.add_subparsers(dest="command", required=True)
    parser.add_argument(
        "--debug", action="store_true", help="Log every parse, classification, and anchor decision with its origin"
    )
    parser.add_argument("--debug-log", type=Path, help="Write the debug log to this file instead of stderr")
    p = sub.add_parser("extract", help="Build or refresh spec/code-map.json from the model and source")
    p.add_argument("--work", type=Path, required=True, help="Specula output directory containing spec/")
    p.add_argument("--source", type=Path, required=True, help="Source tree the model describes")
    p = sub.add_parser("check", help="Report unclassified elements and invalid anchors")
    p.add_argument("--work", type=Path, required=True)
    p = sub.add_parser("impact", help="Map a source diff onto model elements")
    p.add_argument(
        "--work", type=Path, required=True, help="Directory whose spec/code-map.json describes the old source"
    )
    p.add_argument("--diff", type=Path, required=True)
    p.add_argument("--old-source", type=Path)
    p.add_argument("--new-source", type=Path)
    p.add_argument("--json", type=Path, help="Also write the machine-readable report here")
    p.add_argument(
        "--callgraph",
        choices=["auto", "none"],
        default="auto",
        help="Trace callers of unmapped changed functions with the configured per-language tool (default: auto)",
    )
    p.add_argument("--callgraph-config", type=Path, help="JSON overriding the backend per language and server commands")
    p.add_argument("--callgraph-depth", type=int, default=4, help="Maximum caller levels to walk (default: 4)")
    p = sub.add_parser("scope", help="Stage 2: project an update onto the model and record its disposition")
    p.add_argument("action", choices=["init", "check"])
    p.add_argument("--work", type=Path, required=True, help="Directory with spec/code-map.json (old source map)")
    p.add_argument("--impact", type=Path, help="impact --json output (init only)")
    args = parser.parse_args(argv)
    global DEBUG, DEBUG_STREAM
    DEBUG = [] if args.debug or args.debug_log else None
    DEBUG_STREAM = args.debug_log.open("w") if args.debug_log else None
    try:
        return _run(args)
    finally:
        if DEBUG_STREAM is not None:
            DEBUG_STREAM.close()
            DEBUG_STREAM = None
        elif DEBUG is not None:
            sys.stderr.write("\n".join(DEBUG) + "\n")
        DEBUG = None


def _run(args: argparse.Namespace) -> int:
    try:
        path = args.work / FILENAME
        if args.command == "extract":
            previous = read_map(path) if path.is_file() else None
            data = extract(args.work / "spec", args.source.resolve(), previous)
            write_map(path, data)
            print(f"Wrote {path}\n{_summary(data)}")
            return 0
        if args.command == "check":
            data = read_map(path)
            errors, warnings = check(data)
            print(_summary(data))
            for line in warnings:
                print(f"WARNING: {line}")
            for line in errors:
                print(f"ERROR: {line}")
            print("code map complete" if not errors else f"code map incomplete: {len(errors)} error(s)")
            return 1 if errors else 0
        data = read_map(path)
        if args.command == "scope":
            return _run_scope(args, data)
        graphs: dict[str, CallGraph] = {}
        if args.callgraph != "none":
            config = load_config(args.callgraph_config)
            for side, root in (("new", args.new_source), ("old", args.old_source)):
                if root is not None:  # backends start lazily, only when a hunk needs them
                    graphs[side] = CallGraph(
                        root.resolve(),
                        config,
                        log=_side_logger(side),
                    )
        try:
            report = impact(
                data,
                args.diff.read_text(errors="replace"),
                args.old_source,
                args.new_source,
                graphs.get("new") or graphs.get("old"),
                args.callgraph_depth,
                old_graph=graphs.get("old") if "new" in graphs else None,
            )
            failures = {f"{side}:{k}": v for side, g in graphs.items() for k, v in g.failures.items()}
            if report.get("callgraph") is not None:
                report["callgraph"]["failures"] = failures
        finally:
            for g in graphs.values():
                g.close()
        if args.json:
            args.json.write_text(json.dumps(report, indent=2) + "\n")
        sys.stdout.write(render_impact(report))
        return 0
    except (CodeMapError, CallGraphError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


def _side_logger(side: str) -> Callable[[str], None]:
    def log(message: str) -> None:
        _debug("callgraph", f"[{side}] {message}")

    return log


def _run_scope(args: argparse.Namespace, data: dict[str, Any]) -> int:
    path = args.work / SCOPE_FILE
    if args.action == "init":
        if args.impact is None:
            raise CodeMapError("scope init requires --impact=<impact --json output>")
        report = json.loads(args.impact.read_text())
        previous = json.loads(path.read_text()) if path.is_file() else None
        scope = scope_skeleton(report, data, previous)
        path.write_text(json.dumps(scope, indent=2) + "\n")
        print(
            f"Wrote {path}: {len(scope['hunks'])} hunks, {len(scope['elements'])} elements, "
            f"{len(scope['new_functions'])} new functions to disposition"
        )
        return 0
    scope = json.loads(path.read_text())
    errors, warnings, derived = scope_check(scope, data)
    scope["derived"] = derived if not errors else None
    path.write_text(json.dumps(scope, indent=2) + "\n")
    for line in warnings:
        print(f"WARNING: {line}")
    for line in errors:
        print(f"ERROR: {line}")
    if errors:
        print(f"update scope incomplete: {len(errors)} error(s)")
        return 1
    print(
        f"update scope complete: {derived['disposition']}; affected actions {derived['affected_actions'] or '-'}; "
        f"changed elements {derived['changed_elements'] or '-'}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
