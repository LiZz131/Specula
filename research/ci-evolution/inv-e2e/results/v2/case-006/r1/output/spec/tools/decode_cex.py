#!/usr/bin/env python3
"""Decode a TLC -dumpTrace json counterexample of this suite into a step table
(action inferred from message-bag and per-server state diffs).  Usage:
decode_cex.py <cex.json> [> table.md]"""
import json, sys
d = json.load(open(sys.argv[1]))['counterexample']
states = [s for _, s in sorted(((x[0], x[1]) for x in d['state']), key=lambda p: p[0])]
def mkey(m): return json.dumps(m, sort_keys=True)
def short(m):
    s = f"{m['mtype']} {m['from']}->{m['to']} t{m['term']}"
    if m['mtype'] in ('MsgApp',): s += f" i{m['index']} e{m['entryTerm']} c{m['commit']}"
    if m['mtype'] in ('MsgAppResp',): s += f" i{m['index']}{' rej' if m['reject'] else ''}"
    if m['mtype'] in ('MsgHeartbeat',): s += f" c{m['commit']} ctx={m['ctx']}"
    if m['mtype'] in ('MsgHeartbeatResp',): s += f" ctx={m['ctx']} gstamp={m['gstamp']}"
    if m['mtype'] in ('MsgReadIndex', 'MsgReadIndexResp'): s += f" ctx={m['ctx']} idx={m['index']}"
    if m['mtype'] == 'MsgVoteResp' and m['reject']: s += ' rej'
    return s
rows = ["| # | inferred step | consumed | produced | notable post-state |", "|---|---|---|---|---|"]
for k in range(1, len(states)):
    a, b = states[k-1], states[k]
    am = {mkey(m): m for m in a['messages']}; bm = {mkey(m): m for m in b['messages']}
    cons = [am[x] for x in am if x not in bm]; prod = [bm[x] for x in bm if x not in am]
    changed = [v for v in b if v not in ('messages',) and a.get(v) != b.get(v)]
    fc_a, fc_b = a.get('faultCounters', {}), b.get('faultCounters', {})
    fc = [f for f in fc_b if fc_a.get(f) != fc_b.get(f)]
    nodes = sorted({n for v in ('term','role','commitIndex','logs','pendingReads','readQueue','producedReads','durableTerm','readyOutstanding','alive','appliedIndex')
                    for n in b.get(v, {}) if a.get(v, {}).get(n) != b.get(v, {}).get(n)})
    if cons:
        m = cons[0]; t = m['mtype']
        name = {'MsgVote':'HandleVoteRequest','MsgVoteResp':'HandleVoteResponse','MsgApp':'HandleAppendEntries','MsgAppResp':'HandleAppendResponse',
                'MsgHeartbeat':'HandleHeartbeat','MsgHeartbeatResp':'HandleHeartbeatResponse','MsgReadIndex':'HandleReadIndexRequest',
                'MsgReadIndexResp':'HandleReadIndexResponse'}[t] + f"({m['to']})"
        if 'lose' in fc: name = 'LoseMessage'
    elif 'campaign' in fc: name = f"Campaign({nodes[0] if nodes else '?'})"
    elif 'read' in fc:
        name = 'ClientReadIndex' if any(p['mtype']=='MsgHeartbeat' for p in prod) or b['readStamp'] != a['readStamp'] else 'ForwardReadIndex'
        name += f"({nodes[0] if nodes else (prod[0]['from'] if prod else '?')})"
    elif 'ready' in fc: name = f"ReadyPublish({nodes[0] if nodes else '?'})"
    elif 'heartbeat' in fc: name = f"BroadcastHeartbeat({prod[0]['from'] if prod else '?'})"
    elif 'proposal' in fc: name = f"ClientProposal({nodes[0] if nodes else '?'})"
    elif 'quorumCheck' in fc: name = f"CheckQuorum({nodes[0] if nodes else '?'})"
    elif 'crash' in fc: name = f"Crash/EnvCrashRestart({nodes[0] if nodes else '?'})"
    elif any(b['role'][n] == 'Leader' and a['role'][n] != 'Leader' for n in b['role']): name = f"BecomeLeader({[n for n in b['role'] if b['role'][n]=='Leader' and a['role'][n]!='Leader'][0]})"
    elif 'readyOutstanding' in changed: name = f"ReadyAdvance({nodes[0] if nodes else '?'})"
    elif 'alive' in changed: name = f"Restart({nodes[0] if nodes else '?'})"
    else: name = 'step(' + ','.join(changed) + ')'
    notes = []
    for n in sorted(b['term']):
        if a['term'][n] != b['term'][n] or a['role'][n] != b['role'][n]: notes.append(f"{n}: term {b['term'][n]} {b['role'][n]}")
        if a['commitIndex'][n] != b['commitIndex'][n]: notes.append(f"{n}: commit {b['commitIndex'][n]}")
        if a['readQueue'][n] != b['readQueue'][n]: notes.append(f"{n}: queue {b['readQueue'][n]}")
        pa = {c: v for c, v in a['pendingReads'][n].items()}; pb = {c: v for c, v in b['pendingReads'][n].items()}
        for c in pb:
            if pa[c] != pb[c]:
                v = pb[c]; notes.append(f"{n}: pending[{c}] " + (f"active idx={v['index']} stamp={v['stamp']} acks={v['acks']} gcommit={v['gcommit']}" if v['active'] else 'freed'))
    if a['readStamp'] != b['readStamp']: notes.append(f"readStamp {b['readStamp']}")
    if a['servedReads'] != b['servedReads']:
        for sr in b['servedReads']:
            if sr not in a['servedReads']: notes.append(f"served {sr['leader']}@t{sr['term']} ctx={sr['ctx']} index={sr['index']} acks={sr['acks']} freshAcks={sr['freshAcks']} gcommit={sr['gcommit']}")
    if a['commitHistory'] != b['commitHistory']: notes.append('commitHistory ' + str(sorted(c['index'] for c in b['commitHistory'])))
    rows.append(f"| {k+1} | {name} | {'; '.join(short(m) for m in cons)} | {'; '.join(short(m) for m in prod)} | {'; '.join(notes)} |")
print('\n'.join(rows))
