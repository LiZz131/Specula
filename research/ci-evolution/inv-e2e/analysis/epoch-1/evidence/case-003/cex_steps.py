"""Summarise a TLC counterexample: one line per step (action, message changes) plus the
changed values of the variables in KEEP.  usage: cex_steps.py <tlc.log> [var,var,...]"""
import os, re, sys
KEEP = ['phase', 'stateHeight', 'blockStoreHeight', 'appHeight', 'activeParam', 'persistedParam', 'pendingParam', 'pendingAbciPresent', 'pendingBlockHeight', 'updatePresent', 'validationOutcome', 'rejectRule']
if len(sys.argv) > 2: KEEP = sys.argv[2].split(',')
def recs(s):
    out = []; depth = 0; start = None
    for i, ch in enumerate(s):
        if ch == '[':
            if depth == 0: start = i
            depth += 1
        elif ch == ']':
            depth -= 1
            if depth == 0: out.append(s[start:i + 1])
    return [r for r in out if 'mtype |->' in r]
def msum(r):
    g = lambda k: (re.search(k + r' \|-> ("?[\w]+"?)', r) or [None, '?'])[1].strip('"')
    return f"{g('mtype')} {g('from')}->{g('to')} t{g('term')} ctx={g('ctx')}" + (f" idx={g('index')}" if 'ReadIndexResp' in g('mtype') else '')
txt = open(sys.argv[1], errors='replace').read()
# map "MCNext line N" style labels back to the disjunct text when TLC cannot name the action
blocks = [b.split('\n\n')[0] for b in re.split(r'\n(?=State \d+: )', txt) if re.match(r'State \d+: ', b)]
prev = {}; pm = []
for b in blocks:
    n = re.match(r'State (\d+): (.*)', b)
    act = (re.search(r'<(\w+(?:\([^)]*\))?)', n.group(2)) or [None, n.group(2)[:40]])[1]
    ln = re.search(r'line (\d+), col \d+ to line \d+, col \d+ of module (\w+)>', n.group(2))
    if ln and not re.search(r'\(', act or ''):
        try:  # TLC printed only the enclosing disjunction: show the disjunct's source text
            d = os.environ.get('SPEC_DIR') or os.path.dirname(os.path.abspath(sys.argv[1]))
            src = open(os.path.join(d, ln.group(2) + '.tla')).read().split('\n')
            act += ' {' + src[int(ln.group(1)) - 1].strip().lstrip('\\/').strip() + '}'
        except OSError:
            pass
    V = {m.group(1): m.group(2) for m in re.finditer(r'^/\\ (\w+) = (.*?)(?=\n/\\ |\Z)', b, re.S | re.M)}
    ms = recs(V.get('messages', '')); add = [x for x in ms if x not in pm]; rem = [x for x in pm if x not in ms]
    line = f"[{n.group(1)}] {act}"
    if add: line += "  +" + " ; +".join(msum(x) for x in add)
    if rem: line += "  -" + " ; -".join(msum(x) for x in rem)
    print(line)
    for k in KEEP:
        if k in V and ' '.join(V[k].split()) != ' '.join(prev.get(k, '').split()) and n.group(1) != '1':
            print(f"      {k}: {' '.join(V[k].split())}")
    prev = V; pm = ms
