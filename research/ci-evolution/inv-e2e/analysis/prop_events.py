#!/usr/bin/env python3
"""Mechanical property-evolution table: what each arm did to every prior and new property.

    python3 analysis/prop_events.py [--case C ...] [--out analysis/out]

Reads only committed data: the prior suite (blind V0), each run's exported spec
(results/<arm>/<case>/r1/output/spec, top-level .tla/.cfg only), the run's
invariant-evidence.json, and v2's annotation ledger. Writes prop_events.json and
one prop_events-<case>.md per case.

Per prior property and arm:
- def: same | changed | deleted (formula text with comments and whitespace removed);
- helpers_changed: operators in the property's transitive definition closure (old or new) whose
  own text changed, were added or were removed. A property with `def: same` but changed helpers
  still changed meaning;
- cfg_before / cfg_after: number of cfg files that check it (active lines only); dropped_from:
  cfg names that checked it before and still exist but no longer check it;
- evidence: the arm's invariant-evidence decision and kind for it (v1/v2), else "-";
- ledger: the v2 annotation status.
New properties: checked after but not before, with the evidence decision if any.

This table is a starting point for judgment, not a verdict: it cannot tell whether a change was
right, and it misses changes made only in actions, constraints or constants.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
from check_annotation import properties  # noqa: E402
from common import ARMS, HERE, RESULTS, V0_ROOT  # noqa: E402

DEF = re.compile(r"^([A-Za-z_]\w*)\s*(\([^)]*\))?\s*==(.*?)(?=^\S|\Z)", re.S | re.M)
IDENT = re.compile(r"[A-Za-z_]\w*")
LEDGER = re.compile(r"^\\\*\s*REQ-EVIDENCE\s+(\w+)\s*\n\\\*\s*intent:.*\n\\\*\s*status:\s*([\w-]+)", re.M)


def strip(text: str) -> str:
    text = re.sub(r"\(\*.*?\*\)", "", text, flags=re.S)
    return "\n".join(re.sub(r"\\\*.*$", "", l).rstrip() for l in text.splitlines())


def defs(spec: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    # Copies of the prior model (OldBase.tla, PriorMC.tla, ...) must not shadow the current definitions.
    stale = re.compile(r"^(old|prior|prev|v0)", re.I)
    for f in sorted(spec.glob("*.tla"), key=lambda f: (bool(stale.match(f.name)), f.name)):
        if "TTrace" in f.name:
            continue
        for m in DEF.finditer(strip(f.read_text(errors="replace"))):
            out.setdefault(m.group(1), re.sub(r"\s+", " ", (m.group(2) or "") + "==" + m.group(3)).strip())
    return out


def closure(name: str, d: dict[str, str]) -> set[str]:
    seen, todo = set(), [name]
    while todo:
        n = todo.pop()
        if n in seen or n not in d:
            continue
        seen.add(n)
        todo.extend(i for i in IDENT.findall(d[n]) if i in d and i not in seen)
    seen.discard(name)
    return seen


def checked(spec: Path) -> dict[str, list[str]]:
    res: dict[str, list[str]] = {}
    for f in sorted(spec.glob("*.cfg")):
        if "TTrace" in f.name:
            continue
        active = "\n".join(l for l in f.read_text(errors="replace").splitlines() if not l.strip().startswith("\\*"))
        for p in properties(active):
            res.setdefault(p, []).append(f.name)
    return res


def evidence(run: Path) -> dict[str, dict]:
    f = run / "invariant-evidence.json"
    if not f.is_file():
        return {}
    out = {}
    for e in json.loads(f.read_text()).get("entries", []):
        if isinstance(e, dict) and e.get("property"):
            out.setdefault(e["property"], e)
    return out


def ledger(case: str) -> dict[str, str]:
    spec = HERE / "inputs" / case / "annotated" / "spec"
    out = {}
    for f in spec.glob("*.tla"):
        for m in LEDGER.finditer(f.read_text(errors="replace")):
            out[m.group(1)] = m.group(2)
    return out


def analyze(case: str) -> dict:
    prior = V0_ROOT / case / ".specula-output" / "spec"
    od, oc = defs(prior), checked(prior)
    led = ledger(case)
    result = {"case": case, "prior_properties": sorted(oc), "arms": {}}
    for arm in ARMS:
        run = RESULTS / arm / case / "r1"
        spec = run / "output" / "spec"
        if not spec.is_dir():
            continue
        nd, nc = defs(spec), checked(spec)
        ev = evidence(run)
        rows = []
        for p in sorted(oc):
            o, n = od.get(p), nd.get(p)
            state = "deleted" if n is None else ("same" if o == n else "changed")
            helpers = sorted(h for h in closure(p, od) | closure(p, nd) if od.get(h) != nd.get(h))
            dropped = sorted(c for c in oc[p] if (spec / c).is_file() and c not in nc.get(p, []))
            e = ev.get(p, {})
            rows.append({"property": p, "ledger": led.get(p, "-"), "def": state, "helpers_changed": helpers,
                         "cfg_before": len(oc[p]), "cfg_after": len(nc.get(p, [])), "dropped_from": dropped,
                         "evidence": f'{e.get("decision", "-")}/{e.get("kind", "-")}' if e else "-",
                         "evidence_initial": e.get("initial_decision", "-") if e else "-"})
        new = []
        for p in sorted(set(nc) - set(oc)):
            e = ev.get(p, {})
            new.append({"property": p, "cfg_after": len(nc[p]), "in_prior_defs": p in od,
                        "evidence": f'{e.get("decision", "-")}/{e.get("kind", "-")}' if e else "-",
                        "replaces": e.get("replaces") if e else None})
        result["arms"][arm] = {"prior": rows, "new": new,
                               "evidence_only": sorted(set(ev) - set(oc) - set(nc))}
    return result


def markdown(r: dict) -> str:
    arms = [a for a in ARMS if a in r["arms"]]
    out = [f"# {r['case']}: property events (mechanical)\n",
           "Generated by `analysis/prop_events.py`. `def`: formula text; `helpers`: changed operators in its "
           "definition closure; `cfg`: number of cfgs checking it before→after; `drop`: cfgs that still exist but "
           "stopped checking it; `ev`: evidence decision/kind (v1, v2).\n",
           "## Prior properties\n",
           "| property | ledger | " + " | ".join(arms) + " |", "|---|---|" + "---|" * len(arms)]
    for i, p in enumerate(r["prior_properties"]):
        cells = []
        for a in arms:
            x = r["arms"][a]["prior"][i]
            bits = [x["def"]]
            if x["helpers_changed"]:
                bits.append("helpers: " + ", ".join(x["helpers_changed"][:6]) + ("…" if len(x["helpers_changed"]) > 6 else ""))
            bits.append(f'cfg {x["cfg_before"]}→{x["cfg_after"]}')
            if x["dropped_from"]:
                bits.append("drop: " + ", ".join(x["dropped_from"]))
            if x["evidence"] != "-":
                bits.append("ev " + x["evidence"])
            cells.append("; ".join(bits))
        led = r["arms"][arms[0]]["prior"][i]["ledger"]
        out.append(f"| {p} | {led} | " + " | ".join(cells) + " |")
    out.append("\n## New checked properties\n")
    for a in arms:
        rows = r["arms"][a]["new"]
        out.append(f"**{a}** ({len(rows)}): " + (", ".join(
            f'{x["property"]}' + (f' [{x["evidence"]}]' if x["evidence"] != "-" else "") for x in rows) or "none") + "\n")
    return "\n".join(out) + "\n"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--case", action="append")
    ap.add_argument("--out", type=Path, default=HERE / "analysis" / "out")
    a = ap.parse_args()
    cases = a.case or sorted({p.name for arm in ARMS for p in (RESULTS / arm).glob("case-*")})
    a.out.mkdir(parents=True, exist_ok=True)
    allr = []
    for c in cases:
        r = analyze(c)
        allr.append(r)
        (a.out / f"prop_events-{c}.md").write_text(markdown(r))
    (a.out / "prop_events.json").write_text(json.dumps(allr, indent=1, ensure_ascii=False) + "\n")
    for r in allr:
        for arm, d in r["arms"].items():
            rows = d["prior"]
            print(f'{r["case"]} {arm}: prior {len(rows)} | changed {sum(x["def"]=="changed" for x in rows)} '
                  f'deleted {sum(x["def"]=="deleted" for x in rows)} helper-only {sum(x["def"]=="same" and bool(x["helpers_changed"]) for x in rows)} '
                  f'unchecked {sum(x["cfg_after"]==0 for x in rows)} dropped {sum(bool(x["dropped_from"]) for x in rows)} | new {len(d["new"])}')


if __name__ == "__main__":
    main()
