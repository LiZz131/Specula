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
from collections.abc import Iterable
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

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


def _debug(stage: str, message: str) -> None:
    if DEBUG is not None:
        DEBUG.append(f"[{stage}] {message}")


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
        if not match or match.group(1) in NOT_FUNCTIONS:
            continue
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
    functions = {
        f.name for f in source.functions(path) if f.start <= end and start <= f.end and f.name not in NOT_FUNCTIONS
    }
    if functions:
        anchor["functions"] = sorted(functions)
        # A function-level anchor covers a function's start; a line anchor inside a body does not.
        anchor["covers"] = sorted(f.name for f in source.functions(path) if start <= f.start <= end)
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
                for key in ("problem", "functions", "covers"):
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
    return added - removed - NOT_FUNCTIONS


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


def impact(
    data: dict[str, Any], diff_text: str, old_root: Path | None = None, new_root: Path | None = None
) -> dict[str, Any]:
    old = SourceTree(old_root) if old_root else None
    new = SourceTree(new_root) if new_root else None
    elements: dict[str, dict[str, Any]] = data["elements"]
    by_path: dict[str, list[tuple[str, dict[str, Any]]]] = {}
    by_function: dict[str, set[str]] = {}
    for name, entry in elements.items():
        for anchor in _valid_code(entry):
            by_path.setdefault(anchor["path"], []).append((name, anchor))
            covered = anchor["covers"] if "covers" in anchor else anchor.get("functions", [])
            for function in covered + ([anchor["symbol"]] if anchor.get("symbol") else []):
                by_function.setdefault(function, set()).add(name)
    projections = {
        name: IDENT.findall(
            str(
                entry["projection"].get("code", "") if isinstance(entry["projection"], dict) else entry["projection"]
            ).split("(")[0]
        )
        for name, entry in elements.items()
        if entry.get("projection")
    }
    hunks: list[dict[str, Any]] = []
    direct: dict[str, list[str]] = {}
    hidden: dict[str, list[str]] = {}
    for hunk in parse_diff(diff_text):
        functions = _hunk_functions(hunk, old, new)
        first = (hunk.new_lines or hunk.old_lines or [hunk.new_start])[0]
        location = f"{hunk.path}:{first}"
        label = f"{location} ({', '.join(sorted(functions)) or hunk.context or 'no function'})"
        hits: dict[str, str] = {}
        if hunk.old_path:
            for name, anchor in by_path.get(hunk.old_path, []):
                start, stop = anchor["lines"]
                if any(start <= line <= stop for line in hunk.old_lines):
                    hits.setdefault(name, f"lines overlap {anchor['path']}:{start}-{stop}")
        for function in functions:
            for name in by_function.get(function, ()):
                hits.setdefault(name, f"function {function}")
        changed = " ".join(line[1:] for line in hunk.text)
        for name, tokens in projections.items():
            if tokens and any(re.search(rf"\b{re.escape(t)}\b", changed) for t in tokens):
                hits.setdefault(name, f"uses projection {tokens[0]}")
        state_hits = []
        for item in data.get("code_state", []):
            matched = [t for t, pattern in _state_patterns(str(item.get("code", ""))) if pattern.search(changed)]
            if matched:
                state_hits.append(str(item.get("code")))
                for name in item.get("affects", []):
                    hidden.setdefault(name, []).append(f"{label} touches hidden state {', '.join(matched)}")
        scope = next(
            (
                item
                for item in data.get("out_of_scope", [])
                if fnmatch.fnmatch(hunk.path, str(item.get("path", "")))
                and (not item.get("symbol") or item.get("symbol") in functions)
            ),
            None,
        )
        new_functions = _added_functions(hunk, Path(hunk.path).suffix[1:])
        if old is not None and hunk.old_path and (old.root / hunk.old_path).is_file():
            new_functions -= {f.name for f in old.functions(hunk.old_path)}  # changed signatures are not new
        _debug(
            "impact",
            f"hunk {hunk.path}: old changed lines {_ranges(hunk.old_lines)}, new changed lines {_ranges(hunk.new_lines)}; "
            f"enclosing functions {sorted(functions) or '-'}",
        )
        for name, reason in hits.items():
            direct.setdefault(name, []).append(f"{label}: {reason}")
            _debug("impact", f"  -> {name} by {reason}")
        for state in state_hits:
            _debug("impact", f"  -> hidden state {state} named in changed lines")
        if not hits and not state_hits:
            _debug(
                "impact",
                f"  -> {'declared out of scope: ' + str(scope.get('reason')) if scope else 'UNMAPPED: no anchor, function, projection, or code_state matched'}",
            )
        if new_functions:
            _debug(
                "impact", f"  -> new functions {sorted(new_functions)} (defined in + lines, absent from the old file)"
            )
        if hits or state_hits:
            status = "mapped"
        elif scope:
            status = "declared-out-of-scope"
        else:
            status = "unmapped"
        hunks.append(
            {
                "location": location,
                "functions": sorted(functions),
                "status": status,
                "elements": sorted(hits),
                "hidden_state": state_hits,
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
    return {
        "version": VERSION,
        "map_source_commit": data.get("source_commit"),
        "direct": {name: direct[name] for name in sorted(direct)},
        "hidden_state": hidden,
        "propagated": readers,
        "hunks": hunks,
        "summary": {
            "hunks": len(hunks),
            "mapped": sum(h["status"] == "mapped" for h in hunks),
            "declared_out_of_scope": sum(h["status"] == "declared-out-of-scope" for h in hunks),
            "unmapped": sum(h["status"] == "unmapped" for h in hunks),
            "new_functions": sorted({f for h in hunks for f in h["new_functions"]}),
        },
    }


def render_impact(report: dict[str, Any]) -> str:
    s = report["summary"]
    out = [
        "# Code-map impact",
        "",
        f"Map source commit: `{report.get('map_source_commit') or 'unknown'}`. "
        f"Hunks: {s['hunks']}; mapped {s['mapped']}; declared out of scope {s['declared_out_of_scope']}; "
        f"**unmapped {s['unmapped']}**.",
        "",
        "This report orders review; it never proves a change irrelevant. Read the complete diff.",
        "",
        "## Directly affected model elements",
        "",
        "Each of these must appear in the Chapter 1 projection with an explicit conclusion.",
        "",
    ]
    out += [f"- **{name}**: " + "; ".join(reasons) for name, reasons in report["direct"].items()] or ["- none"]
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
    unmapped = [h for h in report["hunks"] if h["status"] == "unmapped"]
    out += [
        "",
        "## Unmapped hunks",
        "",
        "No model element cites this code. Do not skip them: for each, decide whether it changes modeled behavior "
        "through callers, shared state, or assumptions; is outside the modeling scope (record it in out_of_scope); "
        "or reveals a missing map entry.",
        "",
    ]
    out += [f"- {h['location']} ({', '.join(h['functions']) or 'no function'})" for h in unmapped] or ["- none"]
    scoped = [h for h in report["hunks"] if h["status"] == "declared-out-of-scope"]
    if scoped:
        out += ["", "## Declared out of scope", "", "Confirm the recorded reason still holds.", ""]
        out += [f"- {h['location']}: {h['out_of_scope_reason']}" for h in scoped]
    if s["new_functions"]:
        out += [
            "",
            "## New functions",
            "",
            "A new entry point, message handler, timer, or callback can require a new Action or environment step.",
            "",
            "- " + ", ".join(s["new_functions"]),
        ]
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# CLI


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
    args = parser.parse_args(argv)
    global DEBUG
    DEBUG = [] if args.debug or args.debug_log else None
    try:
        return _run(args)
    finally:
        if DEBUG is not None:
            text = "\n".join(DEBUG) + "\n"
            if args.debug_log:
                args.debug_log.write_text(text)
            else:
                sys.stderr.write(text)
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
        report = impact(data, args.diff.read_text(errors="replace"), args.old_source, args.new_source)
        if args.json:
            args.json.write_text(json.dumps(report, indent=2) + "\n")
        sys.stdout.write(render_impact(report))
        return 0
    except (CodeMapError, OSError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
