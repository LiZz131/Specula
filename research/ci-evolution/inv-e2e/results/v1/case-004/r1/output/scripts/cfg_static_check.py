#!/usr/bin/env python3
"""Static cfg preflight: every SPECIFICATION/INVARIANTS/PROPERTIES name and every
CONSTANT in a cfg must be defined/declared in the module chain (no TLC run)."""
import re, sys, pathlib
spec = pathlib.Path(sys.argv[1])
mods = {m: (spec / f"{m}.tla").read_text() for m in ["base", "MC", "Update", "Trace"]}
chain = {"base": ["base"], "MC": ["base", "MC"], "Update": ["base", "MC", "Update"], "Trace": ["base", "Trace"]}
def defs(ms):
    names, consts = set(), set()
    for m in ms:
        t = re.sub(r"\(\*.*?\*\)", "", mods[m], flags=re.S)
        names |= set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\([^)]*\))?\s*==", t, re.M))
        for blk in re.findall(r"^CONSTANTS?(.*?)(?:^\s*$|^ASSUME|^VARIABLES?)", t, re.M | re.S):
            consts |= set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*", blk))
    return names, consts
ok = True
for cfg in sorted(spec.glob("*.cfg")):
    name = cfg.stem
    mod = "Update" if name.startswith("Update") else "Trace" if name.startswith("Trace") else "base" if name == "base" else "MC"
    names, consts = defs(chain[mod])
    sec, used_c, used_n = None, set(), set()
    for line in cfg.read_text().splitlines():
        line = line.split("\\*")[0].strip()
        if not line: continue
        if line in ("CONSTANTS", "CONSTANT", "INVARIANTS", "INVARIANT", "PROPERTIES", "PROPERTY") or line.startswith("SPECIFICATION"):
            sec = line.split()[0]
            if sec == "SPECIFICATION": used_n.add(line.split()[1])
            continue
        if sec and sec.startswith("CONSTANT"):
            used_c.add(line.split("=")[0].strip())
        elif sec in ("INVARIANTS", "INVARIANT", "PROPERTIES", "PROPERTY"):
            used_n.add(line)
    miss_n = used_n - names; miss_c = used_c - consts; unset = consts - used_c
    status = "OK" if not (miss_n or miss_c or unset) else "FAIL"
    if status == "FAIL": ok = False
    print(f"{cfg.name:52s} module={mod:6s} {status} missing_ops={sorted(miss_n)} missing_consts={sorted(miss_c)} unassigned={sorted(unset)}")
sys.exit(0 if ok else 1)
