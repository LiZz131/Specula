#!/usr/bin/env python3
"""Decode a TLC error trace into a per-step summary of changed variables and
the inferred reference Action (base.tla).  usage: decode_ce.py <tlc.log>"""
import re, sys
text = open(sys.argv[1]).read()
blocks = re.findall(r"^State (\d+): <([^\n]*)>\n(.*?)(?=^State \d+:|\n\n)", text, re.S | re.M)
def parse(body):
    st = {}
    for p in re.split(r"^/\\ ", body, flags=re.M):
        p = p.strip()
        if p:
            k, v = p.split(" = ", 1); st[k.strip()] = " ".join(v.split())
    return st
def fields(v):
    # split a TLC function value [a |-> x, b |-> y] or (a :> x @@ b :> y) into a dict
    v = v.strip()
    out = {}
    if v.startswith("[") and "|->" in v:
        inner = v[1:-1]
    elif v.startswith("(") and ":>" in v:
        inner = v[1:-1].replace("@@", ",").replace(":>", "|->")
    else:
        return None
    depth = 0; cur = ""; parts = []
    for ch in inner:
        if ch in "[(<{": depth += 1
        if ch in "])>}": depth -= 1
        if ch == "," and depth == 0:
            parts.append(cur); cur = ""
        else:
            cur += ch
    parts.append(cur)
    for p in parts:
        if "|->" in p:
            k, x = p.split("|->", 1); out[k.strip()] = x.strip()
    return out
def short(v):
    return v.replace("[id |-> ", "").replace(", epoch |-> ", "@").replace("]", "]")
prev = None
for n, label, body in blocks:
    st = parse(body)
    if prev is None:
        print("State %s: Init" % n); prev = st; continue
    ch = []
    for k in st:
        if st[k] != prev.get(k) and k not in ("rollbackAuthorized", "seen", "everCommitted", "counters"):
            a, b = fields(prev[k]), fields(st[k])
            if a is not None and b is not None and set(a) == set(b):
                ch.append("%s{%s}" % (k, ", ".join("%s:%s" % (s, short(b[s])) for s in b if a[s] != b[s])))
            else:
                ch.append("%s=%s" % (k, short(st[k])[:120]))
    print("State %s: %s" % (n, "; ".join(ch)))
    prev = st
