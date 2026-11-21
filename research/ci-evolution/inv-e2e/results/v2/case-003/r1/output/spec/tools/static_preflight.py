#!/usr/bin/env python3
"""Static Generation preflight: cfg operator resolution and per-action variable coverage.
No TLC exploration is performed."""
import re, sys, os, glob
d = os.path.dirname(os.path.abspath(__file__)) + "/.."
def defs(mod, seen=None):
    seen = seen or set()
    if mod in seen or not os.path.exists(f"{d}/{mod}.tla"): return set()
    seen.add(mod)
    s = open(f"{d}/{mod}.tla").read()
    names = set(re.findall(r"^([A-Za-z_][A-Za-z0-9_]*)\s*(?:\([^)]*\))?\s*==", s, re.M))
    for c in re.findall(r"^CONSTANTS?\s+(.*?)(?=\n\S|\n\n)", s, re.M | re.S):
        names |= set(re.findall(r"([A-Za-z_][A-Za-z0-9_]*)\s*(?:,|$|\\\*)", c, re.M))
    ext = re.search(r"^EXTENDS\s+(.*)$", s, re.M)
    if ext:
        for m in [x.strip() for x in ext.group(1).split(",")]:
            names |= defs(m, seen)
    return names
ok = True
cfgmod = {}
for cfg in sorted(glob.glob(f"{d}/*.cfg")):
    b = os.path.basename(cfg)
    mod = "Update" if b.startswith("Update_") else "Trace" if b.startswith("Trace") else "base" if b == "base.cfg" else "MC"
    names = defs(mod)
    txt = open(cfg).read()
    txt = re.sub(r"\\\*.*", "", txt)
    refs = []
    for kw in ["SPECIFICATION", "INIT", "NEXT"]:
        refs += re.findall(rf"^{kw}\s+(\w+)", txt, re.M)
    for blk in re.findall(r"^(?:INVARIANTS?|PROPERTIES|PROPERTY)\s*\n?((?:\s*\w+\s*\n?)+)", txt, re.M):
        refs += re.findall(r"\w+", blk)
    refs += re.findall(r"<-\s*(\w+)", txt)
    refs += re.findall(r"^\s*(\w+)\s*(?:=|<-)", txt, re.M)
    missing = [r for r in refs if r not in names and r not in ("CONSTANTS","INVARIANTS","PROPERTIES","INVARIANT")]
    print(f"{b:45s} module={mod:6s} refs={len(refs):2d} missing={missing}")
    ok &= not missing
# per-action variable coverage in base.tla
s = open(f"{d}/base.tla").read()
vars_ = re.search(r"vars == <<(.*?)>>", s, re.S).group(1)
V = [v.strip() for v in vars_.split(",")]
acts = re.findall(r"^(\w+(?:\([^)]*\))?) ==\n((?:    .*\n|\n)+?)(?=^\S)", s, re.M)
for name, body in acts:
    if "'" not in body and "UNCHANGED vars" not in body: continue
    if "UNCHANGED vars" in body:
        print(f"action {name:35s} UNCHANGED vars"); continue
    primed = set(re.findall(r"(\w+)'", body))
    unch = set()
    for u in re.findall(r"UNCHANGED\s*<<(.*?)>>", body, re.S):
        unch |= {x.strip() for x in u.split(",")}
    missing = [v for v in V if v not in primed and v not in unch]
    both = [v for v in V if v in primed and v in unch]
    print(f"action {name:35s} missing={missing} doubly={both}")
    ok &= not missing and not both
print("PREFLIGHT", "OK" if ok else "FAILED")
