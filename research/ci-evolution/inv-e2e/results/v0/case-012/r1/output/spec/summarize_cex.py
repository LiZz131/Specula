#!/usr/bin/env python3
"""Print selected variables of each state of a TLC counterexample log."""
import re, sys
log = open(sys.argv[1]).read()
keys = sys.argv[2].split(",") if len(sys.argv) > 2 else None
states = re.split(r'\n(?=State \d+:)', log)
for st in states[1:]:
    lines = st.split('\n')
    print(lines[0][:120])
    d = {}; cur = None
    for line in lines[1:]:
        m = re.match(r'/\\ (\w+) = (.*)', line.strip())
        if m: cur = m.group(1); d[cur] = m.group(2)
        elif cur and line.strip() and not re.match(r'(State|Progress|Finished|The |Trace|CMD|EXIT|\d+ states)', line.strip()): d[cur] += ' ' + line.strip()
        elif re.match(r'\d+ states|Progress|Finished', line.strip()): cur = None
    for k in (keys or d.keys()):
        if k in d: print('   ', k, '=', re.sub(r'\s+', ' ', d[k])[:300])
