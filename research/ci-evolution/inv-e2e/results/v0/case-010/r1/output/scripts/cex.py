#!/usr/bin/env python3
"""Summarize a TLC counterexample: action per state, and selected variables for the last N states."""
import re, sys
log = open(sys.argv[1]).read()
vars_ = sys.argv[2].split(',') if len(sys.argv) > 2 and sys.argv[2] else []
lastn = int(sys.argv[3]) if len(sys.argv) > 3 else 3
blocks = re.split(r'\n(?=State \d+: )', log)
states = [b for b in blocks if re.match(r'State \d+: ', b)]
for b in states:
    m = re.match(r'State (\d+): <?([^\n>]*)', b)
    print(m.group(1), m.group(2).split(' line ')[0])
for b in (states[-lastn:] if lastn > 0 else []):
    m = re.match(r'State (\d+):', b)
    print('---- state', m.group(1))
    for v in vars_:
        mm = re.search(r'/\\ ' + re.escape(v) + r' = (.*?)(?=\n/\\ |\n\n|\Z)', b, re.S)
        if mm: print(f'  {v} = {" ".join(mm.group(1).split())}')
