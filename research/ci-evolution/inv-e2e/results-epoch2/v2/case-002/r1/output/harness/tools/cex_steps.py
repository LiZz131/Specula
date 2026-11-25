"""Print, per counterexample step, which variables changed (compact)."""
import re, sys
text = open(sys.argv[1]).read()
parts = re.split(r'\nState (\d+): ([^\n]*)\n', text)
states = []
for i in range(1, len(parts) - 2, 3):
    body = parts[i + 2].split('\n\n')[0]
    vals = {}
    for m in re.finditer(r'^/\\ (\w+) = (.*?)(?=^/\\ |\Z)', body, re.M | re.S):
        vals[m.group(1)] = re.sub(r'\s+', ' ', m.group(2)).strip()
    states.append((int(parts[i]), vals))
keys = sys.argv[2].split(',') if len(sys.argv) > 2 else None
prev = None
for n, v in states:
    if prev is None:
        prev = v; continue
    ch = [k for k in v if v[k] != prev.get(k)]
    show = {k: v[k] for k in ch if (keys is None or k in keys)}
    print(n, ','.join(ch), '|', '; '.join('%s=%s' % (k, s[:160]) for k, s in show.items()))
    prev = v
