#!/usr/bin/env python3
"""Summarize a TLC counterexample log: action per state and the per-node values of chosen variables."""
import re, sys
t = open(sys.argv[1]).read()
keys = sys.argv[2].split(",") if len(sys.argv) > 2 else ["voteTerm","voteNode","voteCommitted","role","candidate","leader","up","corePanic","configs","learners","granters"]
i = t.find("The behavior up to this point is:")
if i < 0: i = t.find("The following behavior constitutes a counter-example:")
part = t[i:]
chunks = re.split(r"\nState (\d+): ", part)[1:]
for k in range(0, len(chunks), 2):
    num, body = chunks[k], chunks[k+1]
    head = body.split("\n")[0]
    vals = {}
    for key in keys:
        m = re.search(r"/\\ " + key + r" = (.*?)(?=\n/\\ |\n\n|\Z)", body, re.S)
        if m: vals[key] = " ".join(m.group(1).split())
    print(f"State {num}: {head}")
    for key in keys:
        if key in vals: print(f"    {key} = {vals[key]}")
