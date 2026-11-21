"""Summarize a TLC counterexample: action per step and changed variables."""
import re, sys
txt = open(sys.argv[1]).read()
states = re.findall(r"\nState (\d+): <?([^\n]*)\n(.*?)(?=\nState \d+:|\nBack to state|\n\d+ states generated|\Z)", txt, re.S)
def parse(body):
    d = {}
    for m in re.finditer(r"/\\ (\w+) = (.*?)(?=\n/\\ |\Z)", body, re.S):
        d[m.group(1)] = " ".join(m.group(2).split())
    return d
prev = None
show = sys.argv[2].split(",") if len(sys.argv) > 2 else None
for num, act, body in states:
    cur = parse(body)
    act = re.sub(r" line \d+, col \d+ to line \d+, col \d+ of module \w+", "", act).strip("<> ")
    changes = {k: v for k, v in cur.items() if prev is None or prev.get(k) != v}
    if show: changes = {k: v for k, v in changes.items() if k in show}
    print(f"[{num}] {act}")
    for k, v in changes.items():
        if prev is not None:
            print(f"     {k} = {v[:260]}")
    prev = cur
