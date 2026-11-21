#!/usr/bin/env python3
"""Static cfg preflight: every operator named in a cfg is defined in the module chain."""
import re, sys, pathlib
spec = pathlib.Path(sys.argv[1])
chain = {"base": ["base"], "MC": ["base", "MC"], "MC5": ["base", "MC5"], "Update": ["base", "MC", "Update"], "Trace": ["base", "Trace"]}
defs = {}
for mod in ["base", "MC", "MC5", "Update", "Trace"]:
    text = (spec / f"{mod}.tla").read_text()
    defs[mod] = set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\([^)]*\))?\s*==", text, re.M))
    defs[mod] |= set(re.findall(r"^(?:CONSTANTS?|VARIABLES?)\s+(.*)$", text, re.M) and [])
bad = 0
for cfg in sorted(spec.glob("*.cfg")):
    name = cfg.stem
    mod = "Update" if name.startswith("Update") else "MC5" if name.startswith("MC5") else "MC" if name.startswith("MC") else "Trace" if name.startswith("Trace") else name
    known = set().union(*(defs[m] for m in chain[mod]))
    toks = []
    section = None
    for line in cfg.read_text().splitlines():
        line = line.split("\\*")[0].strip()
        if not line:
            continue
        kw = line.split()[0]
        if kw in ("INIT", "NEXT", "SPECIFICATION", "VIEW", "CONSTRAINT", "INVARIANT", "PROPERTY", "INVARIANTS", "PROPERTIES", "CONSTANTS", "CHECK_DEADLOCK", "SYMMETRY", "ACTION_CONSTRAINT"):
            section = kw
            rest = line.split()[1:]
        else:
            rest = line.split()
        if section in ("INIT", "NEXT", "SPECIFICATION", "VIEW", "CONSTRAINT", "INVARIANT", "PROPERTY", "INVARIANTS", "PROPERTIES", "SYMMETRY", "ACTION_CONSTRAINT"):
            toks += rest
        elif section == "CONSTANTS" and "<-" in rest:
            toks.append(rest[rest.index("<-") + 1])
    missing = [t for t in toks if t not in known]
    print(f"{cfg.name}: module={mod} names={len(toks)} missing={missing}")
    bad += bool(missing)
sys.exit(1 if bad else 0)
