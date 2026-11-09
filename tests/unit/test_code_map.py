"""Code-to-model map extraction, completeness checking, and diff impact."""

from __future__ import annotations

import json
import shutil
import subprocess
from pathlib import Path
from typing import Any

import pytest

from specula import code_map

NODE_C = """\
#include "node.h"

int node_timeout(node_t* me)
{
    if (me->snapshotting)
        return 0;
    me->term += 1;
    me->role = ROLE_CANDIDATE;
    return 0;
}

int node_recv_vote(node_t* me, int term)
{
    if (term > me->term)
        me->term = term;
    return 0;
}

void node_free(node_t* me)
{
    free(me);
}

int node_get_term(node_t* me)
{
    return me->term;
}
"""

NODE_H = """\
typedef enum {
    ROLE_FOLLOWER,
    ROLE_CANDIDATE
} role_e;
"""

BASE_TLA = """\
---- MODULE base ----
EXTENDS Naturals

CONSTANTS
    Server,     \\* Node identities
    MaxTerm     \\* Bound on terms

\\* Roles (node.h:1-4)
CONSTANTS Follower, Candidate

VARIABLES
    term,       \\* node.c:7 me->term

    \\* Role state.
    role        \\* node.c:8, 9

\\* Stray note about cleanup (node.c:19-22)

vars == <<term, role>>

Bump(x) == x + 1

\\*****************************************
\\* node_timeout (node.c:3-10)
\\*****************************************
Timeout(i) ==
    /\\ term' = [term EXCEPT ![i] = Bump(term[i])]
    /\\ role' = [role EXCEPT ![i] = Candidate]

RecvVote(i, t) ==
    \\* term update (node.c:14-15)
    /\\ t > term[i]
    /\\ term' = [term EXCEPT ![i] = t]
    /\\ UNCHANGED <<role>>

Crash(i) ==
    /\\ \\/ /\\ role' = [role EXCEPT ![i] = Follower]
          /\\ term' = term
       \\/ /\\ role' = role
          /\\ term' = [term EXCEPT ![i] = 0]

\\* Wrong file length (node.c:200-210)
Broken(i) ==
    /\\ term' = term
    /\\ UNCHANGED role

Init ==
    /\\ term = [s \\in Server |-> 0]   \\* node.c:7
    /\\ role = [s \\in Server |-> Follower]

Next ==
    \\/ \\E i \\in Server : Timeout(i)
    \\/ \\E i \\in Server, t \\in 1..MaxTerm : RecvVote(i, t)
    \\/ \\E i \\in Server : Crash(i)
    \\/ \\E i \\in Server : Broken(i)

Spec == Init /\\ [][Next]_vars

OneCandidate == \\A i, j \\in Server : role[i] = Candidate /\\ role[j] = Candidate => term[i] # term[j]
====
"""

MC_TLA = """\
---- MODULE MC ----
EXTENDS base
TermBound == \\A i \\in Server : term[i] <= MaxTerm
====
"""

MC_CFG = """\
CONSTANTS
    Server = {s1, s2}
    MaxTerm = 3
    Follower = Follower
    Candidate = Candidate
SPECIFICATION Spec
INVARIANTS
    OneCandidate
    TermBound
"""

TRACE_TLA = """\
---- MODULE Trace ----
EXTENDS base
TraceTimeout ==
    /\\ IsEvent("Timeout")
    /\\ \\E i \\in Server : Timeout(i)
TraceRecvVote ==
    /\\ IsEvent("RecvVote")
    /\\ \\E i \\in Server, t \\in 1..MaxTerm : RecvVote(i, t)
====
"""

INSTRUMENTATION = """\
# Instrumentation

| Implementation getter | TLA+ variable | Field |
|---|---|---|
| `node_get_term(me)` | `term` | `post.term` |

## 2. Action-to-Code Mapping

| Spec action | Code location | Trigger |
|---|---|---|
| `RecvVote` | `node.c:12-17` (`node_recv_vote`) | after update |
"""


def git(repo: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True).stdout.strip()


@pytest.fixture()
def project(tmp_path: Path) -> dict[str, Path]:
    source = tmp_path / "source"
    (source / "src").mkdir(parents=True)
    (source / "include").mkdir()
    (source / "src/node.c").write_text(NODE_C)
    (source / "include/node.h").write_text(NODE_H)
    git(source, "init", "-q")
    git(source, "-c", "user.name=t", "-c", "user.email=t@example.com", "add", ".")
    git(source, "-c", "user.name=t", "-c", "user.email=t@example.com", "commit", "-qm", "initial")
    work = tmp_path / "work"
    spec = work / "spec"
    spec.mkdir(parents=True)
    (spec / "base.tla").write_text(BASE_TLA)
    (spec / "MC.tla").write_text(MC_TLA)
    (spec / "MC.cfg").write_text(MC_CFG)
    (spec / "Trace.tla").write_text(TRACE_TLA)
    (spec / "instrumentation-spec.md").write_text(INSTRUMENTATION)
    return {"source": source, "work": work}


def build(project: dict[str, Path], previous: dict[str, Any] | None = None) -> dict[str, Any]:
    return code_map.extract(project["work"] / "spec", project["source"], previous)


def anchors(entry: dict[str, Any]) -> list[tuple[str, list[int], list[str]]]:
    return [(a["path"], a["lines"], a.get("functions", [])) for a in entry["code"] if "problem" not in a]


def test_extract_classifies_elements_and_resolves_anchors(project: dict[str, Path]) -> None:
    data = build(project)
    elements = data["elements"]
    kinds = {name: entry["kind"] for name, entry in elements.items()}
    assert kinds["Server"] == kinds["Follower"] == "constant"
    assert kinds["term"] == kinds["role"] == "variable"
    assert kinds["vars"] == "var-group"
    assert kinds["Bump"] == "helper"
    assert kinds["Init"] == "init"
    assert {n for n, k in kinds.items() if k == "action"} == {"Timeout", "RecvVote", "Crash", "Broken"}
    assert kinds["OneCandidate"] == kinds["TermBound"] == "property"
    assert elements["Server"]["category"] == "world"
    assert elements["MaxTerm"]["category"] == "bound"
    assert elements["Follower"]["category"] == "enum"

    assert anchors(elements["Timeout"]) == [("src/node.c", [3, 10], ["node_timeout"])]
    assert ("src/node.c", [12, 17], ["node_recv_vote"]) in anchors(elements["RecvVote"])
    assert ("src/node.c", [14, 15], ["node_recv_vote"]) in anchors(elements["RecvVote"])
    assert anchors(elements["Follower"])[0][:2] == ("include/node.h", [1, 4])
    assert anchors(elements["Crash"]) == []

    assert elements["Timeout"]["writes"] == ["role", "term"]
    assert elements["RecvVote"]["writes"] == ["term"]
    assert elements["Crash"]["writes"] == ["role", "term"]  # an identity frame in one branch does not hide another
    assert "role" not in elements["RecvVote"]["reads"]  # UNCHANGED is a frame, not a read
    assert "writes" not in elements["Broken"]  # term' = term is a frame
    assert elements["OneCandidate"]["reads"] == ["role", "term"]
    assert elements["OneCandidate"]["enabled_in"] == ["MC.cfg"]
    assert elements["Timeout"]["trace_events"] == ["Timeout"]
    assert elements["RecvVote"]["trace_events"] == ["RecvVote"]
    assert elements["term"]["projection"] == {"code": "node_get_term(me)", "origin": "instrumentation-spec.md:5"}
    assert elements["Timeout"]["defined_at"] == "base.tla:26"
    assert elements["Timeout"]["reason"].startswith("R-ACTION: base.tla:26 referenced from Next")
    assert elements["vars"]["reason"].startswith("R-VARGROUP")
    assert elements["TermBound"]["reason"].startswith("R-PROPERTY: MC.tla:")
    assert elements["Server"]["category_reason"].startswith("R-CONST: MC.cfg:2")
    assert elements["Timeout"]["code"][0]["origin"] == "base.tla:24"

    issues = {(issue["kind"], issue["element"]) for issue in data["issues"]}
    assert ("invalid-anchor", "Broken") in issues
    assert ("unattached-anchor", "") in issues
    assert data["source_commit"] == git(project["source"], "rev-parse", "HEAD")


def test_check_requires_classification_then_passes(project: dict[str, Path]) -> None:
    data = build(project)
    errors, _ = code_map.check(data)
    text = "\n".join(errors)
    for name in ("Crash", "OneCandidate", "TermBound", "Broken", "Candidate"):
        assert name in text
    assert "Server" not in text and "MaxTerm" not in text  # cfg parameters are classified mechanically

    elements = data["elements"]
    elements["Crash"]["agent"] = {"status": "environment", "note": "process crash; volatile role lost"}
    elements["OneCandidate"]["agent"] = {"status": "requirement", "note": "election safety"}
    elements["TermBound"]["agent"] = {"status": "check-parameter", "note": "bounds exploration"}
    elements["Broken"]["agent"] = {"status": "model-glue", "note": "stutter step"}
    elements["Candidate"]["agent"] = {
        "status": "mapped",
        "code": [{"path": "include/node.h", "lines": [3, 3], "role": "declaration"}],
    }
    errors, warnings = code_map.check(data)
    assert len(errors) == 1 and "Broken" in errors[0] and "outside the file" in errors[0]
    assert any("Bump" in w for w in warnings)
    assert any("cleanup" in w for w in warnings)  # unattached citation

    base = project["work"] / "spec/base.tla"
    base.write_text(base.read_text().replace("Wrong file length (node.c:200-210)", "Stutter step"))
    data = build(project, data)
    errors, _ = code_map.check(data)
    assert errors == []
    elements = data["elements"]

    data["code_state"] = [{"code": "node_t.snapshotting (presence and return values)", "affects": ["Timeout"]}]
    errors, warnings = code_map.check(data)
    assert errors == [] and any("plain words" in w for w in warnings)
    data["code_state"] = [{"code": "presence of callbacks", "affects": ["Timeout"]}]
    errors, _ = code_map.check(data)
    assert any("names no field" in e for e in errors)
    data["code_state"] = []
    elements["Crash"]["agent"] = {"status": "environment"}
    data["out_of_scope"] = [{"path": "src/*.c"}]
    errors, _ = code_map.check(data)
    assert any("Crash" in e and "note" in e for e in errors)
    assert any("out_of_scope[0]" in e for e in errors)


def test_extract_preserves_agent_entries(project: dict[str, Path]) -> None:
    data = build(project)
    data["elements"]["Crash"]["agent"] = {"status": "environment", "note": "crash"}
    data["code_state"] = [{"code": "node_t.snapshotting", "affects": ["Timeout"]}]
    data["elements"]["Gone"] = {"kind": "action", "code": [], "agent": {"status": "mapped"}}
    data["elements"]["Init"]["agent"] = {
        "status": "mapped",
        "code": [{"path": "src/node.c", "lines": [3, 4]}, {"path": "src/node.c", "lines": [90, 95]}],
    }
    refreshed = build(project, data)
    assert refreshed["elements"]["Crash"]["agent"] == {"status": "environment", "note": "crash"}
    init_code = refreshed["elements"]["Init"]["agent"]["code"]
    assert init_code[0]["covers"] == ["node_timeout"] and "problem" not in init_code[0]
    assert "outside the file" in init_code[1]["problem"]
    assert any(i["element"] == "Init" and i["kind"] == "invalid-anchor" for i in refreshed["issues"])
    assert refreshed["code_state"] == data["code_state"]
    assert "Gone" not in refreshed["elements"]
    assert {"element": "Gone", "kind": "removed-element", "detail": "no longer defined in base.tla"} in refreshed[
        "issues"
    ]


def change(project: dict[str, Path], old: str, new: str) -> str:
    """Keep the pre-update tree as project["old"], then edit the source in place."""
    if "old" not in project:
        project["old"] = project["source"].parent / "old-source"
        shutil.copytree(project["source"], project["old"])
    path = project["source"] / "src/node.c"
    path.write_text(path.read_text().replace(old, new))
    return git(project["source"], "diff")


def test_impact_reports_direct_propagated_and_hidden_state(project: dict[str, Path]) -> None:
    data = build(project)
    data["code_state"] = [
        {"code": "node_t.snapshotting / node_t.busy", "affects": ["Timeout"], "note": "guard"},
        {"code": "node_t.term_cache (return values)", "affects": ["RecvVote"], "note": "prose words must not match"},
    ]
    diff = change(
        project,
        "    if (me->snapshotting)\n        return 0;\n",
        "    if (me->snapshotting || me->busy)\n        return 0;\n",
    )
    report = code_map.impact(data, diff, project["old"], project["source"])
    assert list(report["direct"]) == ["Timeout"]
    assert "Timeout" in report["hidden_state"]
    assert "RecvVote" not in report["hidden_state"]
    assert "RecvVote" in report["propagated"]["term"]["actions"]
    assert "OneCandidate" in report["propagated"]["role"]["properties"]
    assert report["summary"]["unmapped"] == 0
    assert "Timeout" in code_map.render_impact(report)


def test_impact_never_drops_unmapped_code(project: dict[str, Path]) -> None:
    data = build(project)
    diff = change(project, "    free(me);\n", "    cleanup(me);\n    free(me);\n")
    report = code_map.impact(data, diff, project["old"], project["source"])
    assert report["direct"] == {}
    assert report["summary"]["unmapped"] == 1
    assert report["hunks"][0]["functions"] == ["node_free"]
    assert "node_free" in code_map.render_impact(report)

    data["out_of_scope"] = [{"path": "src/node.c", "symbol": "node_free", "reason": "memory management"}]
    report = code_map.impact(data, diff, project["old"], project["source"])
    assert report["summary"]["declared_out_of_scope"] == 1
    assert "memory management" in code_map.render_impact(report)


def test_impact_lists_new_functions(project: dict[str, Path]) -> None:
    data = build(project)
    diff = change(
        project,
        "int node_get_term(node_t* me)\n",
        "int node_cancel(node_t* me)\n{\n    return 0;\n}\n\nint node_get_term(node_t* me)\n",
    )
    report = code_map.impact(data, diff, project["old"], project["source"])
    assert report["summary"]["new_functions"] == ["node_cancel"]


def test_cli_round_trip(project: dict[str, Path], capsys: pytest.CaptureFixture[str]) -> None:
    work, source = project["work"], project["source"]
    assert code_map.main(["extract", f"--work={work}", f"--source={source}"]) == 0
    assert (work / code_map.FILENAME).is_file()
    assert code_map.main(["check", f"--work={work}"]) == 1
    assert "code map incomplete" in capsys.readouterr().out
    diff = work / "update.diff"
    diff.write_text(change(project, "me->term += 1;", "me->term += 2;"))
    out_json = work / "impact.json"
    assert (
        code_map.main(
            [
                "impact",
                f"--work={work}",
                f"--diff={diff}",
                f"--old-source={project['old']}",
                f"--new-source={source}",
                f"--json={out_json}",
            ]
        )
        == 0
    )
    assert "Timeout" in json.loads(out_json.read_text())["direct"]
    assert code_map.main(["check", f"--work={work / 'missing'}"]) == 1


def test_debug_log_records_origins(project: dict[str, Path]) -> None:
    log = project["work"] / "debug.log"
    work, source = project["work"], project["source"]
    assert code_map.main(["--debug-log", str(log), "extract", f"--work={work}", f"--source={source}"]) == 0
    text = log.read_text()
    assert "[parse] base.tla:26 definition Timeout with leading comments 24-24" in text
    assert "[classify] Timeout -> action: R-ACTION" in text
    assert "[classify] Send" not in text  # no such element in the fixture
    assert "[cfg] MC.cfg:8 enables property OneCandidate" in text
    assert "[trace] Trace.tla:3 TraceTimeout: event 'Timeout' -> Timeout" in text
    assert "[projection] instrumentation-spec.md:5 table row: term <- node_get_term(me)" in text
    assert "[resolve] Broken [base.tla:42]" in text and "INVALID" in text
    assert "floating" in text
    assert code_map.DEBUG is None


def test_declarations_across_blank_lines_and_multi_ranges(project: dict[str, Path]) -> None:
    elements = build(project)["elements"]
    assert elements["role"]["kind"] == "variable"
    assert [a["lines"] for a in elements["role"]["code"]] == [[8, 8], [9, 9]]


def test_bare_names_are_disambiguated_conservatively(project: dict[str, Path]) -> None:
    other = project["source"] / "test/node.c"
    other.parent.mkdir()
    other.write_text("int x;\n")
    data = build(project)
    timeout = data["elements"]["Timeout"]["code"][0]
    assert timeout["path"] == "src/node.c" and "problem" not in timeout
    assert "has line 10" in timeout["resolved_by"]
    assert any(i["kind"] == "ambiguous-resolved" for i in data["issues"])
    errors, warnings = code_map.check(data)
    assert any("resolved to src/node.c" in w for w in warnings)
    (project["source"] / "test/node.c").write_text("\n" * 100)
    data = build(project)
    assert "ambiguous path" in data["elements"]["Timeout"]["code"][0]["problem"]
