#!/usr/bin/env python3
"""Parse a TLC -dump file into a list of {var: tla_text} states."""
import re, sys, json

def parse(path):
    states, cur, var = [], None, None
    for line in open(path):
        line = line.rstrip('\n')
        m = re.match(r'^State (\d+):', line)
        if m:
            if cur is not None:
                states.append(cur)
            cur, var = {}, None
            continue
        if cur is None:
            continue
        m = re.match(r'^/\\ (\w+) = (.*)$', line)
        if m:
            var = m.group(1)
            cur[var] = m.group(2)
        elif var is not None and line.startswith((' ', '\t')) and line.strip():
            cur[var] += '\n' + line
        elif line.strip():
            var = None  # top-level non-state text (TLC messages) ends the value
    if cur is not None:
        states.append(cur)
    return states

def conj(state, prime=False, skip=(), override=None):
    override = override or {}
    out = []
    for k in sorted(state):
        if k in skip:
            continue
        v = override.get(k, state[k])
        out.append('    /\\ %s%s = %s' % (k, "'" if prime else '', v.replace('\n', '\n       ')))
    return '\n'.join(out)

if __name__ == '__main__':
    st = parse(sys.argv[1])
    print(json.dumps([{k: v[:60] for k, v in s.items() if k in ('cursor','role','preActive','vote')} for s in st], indent=0)[:4000])
