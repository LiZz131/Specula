#!/usr/bin/env python3
"""Summarise a TLC counterexample: action per state + selected variables."""
import re, sys
log = open(sys.argv[1]).read()
keys = sys.argv[2].split(",") if len(sys.argv) > 2 else ["role", "lastLog", "committed", "progress", "witnessIndex", "witnessNodes", "witnessConfig", "matchedIndex", "messages", "effectiveConfig"]
blocks = re.findall(r'State (\d+): <([^>]*)>\n(.*?)(?=\nState \d+:|\n\n|\Z)', log, re.S)
prev = {}
for n, act, body in blocks:
    print("== State", n, act.split(" line")[0])
    for k in keys:
        m = re.search(r'/\\ ' + k + r' = (.*?)(?=\n/\\ |\Z)', body, re.S)
        if m:
            v = " ".join(m.group(1).split())
            if prev.get(k) != v:
                print("   ", k, "=", v[:600])
            prev[k] = v
