#!/usr/bin/env python3
"""Summarise a TLC -dumpTrace json counterexample: per step, the changed variables."""
import json, sys
KEYS = None
def fmt(v):
    s = json.dumps(v, separators=(',', ':'))
    return s if len(s) < 400 else s[:400] + '...'
def main(path, keys=None):
    d = json.load(open(path))
    states = d['counterexample']['state'] if 'state' in d['counterexample'] else d['counterexample']
    prev = None
    for i, st in enumerate(states, 1):
        vals = st[1] if isinstance(st, list) else st
        if isinstance(vals, dict) and 'state' in vals: vals = vals['state']
        if prev is None:
            print(f"--- state {i} (initial)")
        else:
            ch = {k: v for k, v in vals.items() if prev.get(k) != v and (keys is None or k in keys)}
            print(f"--- state {i}: " + "; ".join(f"{k}={fmt(v)}" for k, v in ch.items()))
        prev = vals
if __name__ == '__main__':
    main(sys.argv[1], set(sys.argv[2].split(',')) if len(sys.argv) > 2 else None)
