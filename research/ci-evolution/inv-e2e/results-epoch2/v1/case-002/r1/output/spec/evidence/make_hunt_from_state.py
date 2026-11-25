#!/usr/bin/env python3
"""Build a hunt module whose initial state is state N of a TLC counterexample
(a state reachable from MCInit).  A violation found from it, prefixed by the
source counterexample's first N states, is a behavior of the original spec."""
import re, sys
log, n, mod, nextop = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
txt = open(log).read()
m = re.search(r'^State %d: .*?\n(.*?)(?=^State \d+:|^\d+ states generated|\Z)' % n, txt, re.S | re.M)
if not m: sys.exit("state not found")
conj = []
for part in re.split(r'^/\\ ', m.group(1), flags=re.M):
    part = part.strip()
    if part: conj.append('/\\ ' + part)
init = '\n    '.join(c.replace('\n', '\n    ') for c in conj)
open(f'{mod}.tla', 'w').write(f'''---- MODULE {mod} ----
\\* Hunt continuation from state {n} of {log.split('/spec/')[-1]}
\\* (prefix is a TLC counterexample of the same reference/MC spec from MCInit).
EXTENDS Update
HuntInit ==
    {init}
HuntSpec == HuntInit /\\ [][{nextop}]_vars
====
''')
print("wrote", mod)
