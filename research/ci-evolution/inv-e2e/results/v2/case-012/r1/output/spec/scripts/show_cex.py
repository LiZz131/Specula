#!/usr/bin/env python3
"""Print a TLC JSON counterexample (-dumpTrace json) compactly: actions and changed variables."""
import json, sys
t = json.load(open(sys.argv[1]))
c = t['counterexample']
keys = set(sys.argv[2].split(',')) if len(sys.argv) > 2 and sys.argv[2] else None
states = [s[1] for s in c['state']]
acts = [a[1] for a in c['action']]
def fmt(v): return json.dumps(v, separators=(',', ':'))
prev = None
for k, s in enumerate(states):
    if k == 0:
        print("--- state 1: <Init>")
    else:
        a = acts[k - 1]
        print(f"--- state {k+1}: {a.get('name')} {a.get('context', {})}")
    for var in sorted(s):
        if keys and var not in keys: continue
        if prev is None or prev.get(var) != s[var]:
            if prev is None and keys is None: continue
            print(f"   {var} = {fmt(s[var])}")
    prev = s
