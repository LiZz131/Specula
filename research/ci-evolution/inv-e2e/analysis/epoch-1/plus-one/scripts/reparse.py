#!/usr/bin/env python3
"""Re-parse full TLC logs (work dir) into results; keeps rc/seconds from the original rows.
Usage: reparse.py <results.jsonl> <logdir> <out.jsonl>"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run_jobs import parse
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
seen = {}
for r in rows:
    seen[r['id']] = r  # last row per id wins
with open(sys.argv[3], 'w') as f:
    for r in seen.values():
        log = open(os.path.join(sys.argv[2], r['id'] + '.log'), errors='replace').read()
        r.update(parse(log))
        f.write(json.dumps(r) + '\n')
print(len(seen))
