"""Summarize a TLC -dumpTrace json counterexample step by step.

TLC labels every MC step "MCNext" (the MC next-state relation is a single
conjunction), so the reference Action is inferred from the state diff:
messages added/removed plus changed node/read variables."""
import json, sys

def key(m):
    return (m['mtype'], m['from'], m['to'], m['term'], m['index'], m['commit'], m['ctx'], m['reject'], m.get('rinc', 0), m['entryTerm'])

def mdesc(m):
    s = f"{m['mtype']} {m['from']}->{m['to']} t{m['term']}"
    if m['mtype'] in ('MsgApp',):
        s += f" prev={m['index']} ent={m['entryTerm']} commit={m['commit']}"
    if m['mtype'] in ('MsgAppResp', 'MsgReadIndexResp'):
        s += f" idx={m['index']}"
    if m['mtype'] in ('MsgVoteResp', 'MsgAppResp') and m['reject']:
        s += " REJECT"
    if m['mtype'] in ('MsgHeartbeat',):
        s += f" commit={m['commit']}"
    if m['ctx'] != 'Nil':
        s += f" ctx={m['ctx']} rinc={m.get('rinc', 0)}"
    return s

WATCH = ['role', 'term', 'vote', 'logs', 'commitIndex', 'durableTerm', 'durableVote',
         'durableLogs', 'durableCommit', 'readyOutstanding', 'readQueue', 'readInc',
         'commitHistory', 'readReleases', 'producedReads', 'publishedReads', 'alive',
         'leaderHistory']

def per_node(old, new):
    if isinstance(new, dict) and isinstance(old, dict):
        return {k: new[k] for k in new if old.get(k) != new[k]}
    return new

d = json.load(open(sys.argv[1]))
c = d['counterexample']
states = [s[1] for s in c['state']]
print(f"{len(states)} states")
prev = None
for n, st in enumerate(states, 1):
    if prev is None:
        print(f"  1 Init")
        prev = st
        continue
    pm = {key(m): m for m in prev['messages']}
    nm = {key(m): m for m in st['messages']}
    added = [mdesc(nm[k]) for k in nm if k not in pm]
    removed = [mdesc(pm[k]) for k in pm if k not in nm]
    print(f"{n:>3}" + (f"  consumed/lost: {'; '.join(removed)}" if removed else ""))
    if added:
        print(f"      sent: {'; '.join(added)}")
    for v in WATCH:
        if prev.get(v) != st.get(v):
            ch = per_node(prev.get(v), st.get(v))
            print(f"      {v}: {json.dumps(ch, separators=(',', ':'))[:500]}")
    prev = st
