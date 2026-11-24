#!/usr/bin/env python3
"""Append/replace dismissal items in items.jsonl (keyed by id). stdin: JSON list."""
import json, sys, os
f = os.path.join(os.path.dirname(os.path.abspath(__file__)), "items.jsonl")
items = {}
if os.path.exists(f):
    for l in open(f):
        if l.strip():
            d = json.loads(l); items[d["id"]] = d
for d in json.load(sys.stdin):
    items[d["id"]] = {**items.get(d["id"], {}), **d}
with open(f, "w") as o:
    for d in items.values():
        o.write(json.dumps(d, ensure_ascii=False) + "\n")
print(len(items))
