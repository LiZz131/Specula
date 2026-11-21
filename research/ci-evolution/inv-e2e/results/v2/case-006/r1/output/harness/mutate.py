#!/usr/bin/env python3
"""Negative controls: hand-mutated COPIES of fresh traces (not implementation
traces). Each mutation changes one update-mandatory field; replay must reject
it at that record. Usage: mutate.py <traces-dir>"""
import json, sys, os
T = sys.argv[1]; M = os.path.join(T, 'mutants'); os.makedirs(M, exist_ok=True)
def load(n): return [json.loads(l) for l in open(f'{T}/{n}.ndjson')]
def save(n, recs): open(f'{M}/{n}.ndjson', 'w').write(''.join(json.dumps(r, separators=(',', ':')) + '\n' for r in recs))
def first(recs, pred): return next(k for k, r in enumerate(recs) if pred(r['event']))
notes = []
r = load('quorum_read'); k = first(r, lambda e: e['name'] == 'HandleHeartbeatResponse')
r[k]['event']['state']['pending'] = [{'ctx': 'ctx1', 'index': 2, 'from': 's1', 'acks': [r[k]['event']['msg']['from']]}]
r[k]['event']['state']['pendingCount'] = 1
save('m1_quorum_read_stale_pending', r); notes.append(f'm1_quorum_read_stale_pending: record {k+1} claims the exact-old stale pending entry')
r = load('read_reuse'); k = first(r, lambda e: len(e['state']['readStates']) == 2)
r[k]['event']['state']['readStates'][1]['index'] = 1; save('m2_read_reuse_readindex', r); notes.append(f'm2_read_reuse_readindex: record {k+1} second ReadState index -> 1')
r = load('forwarded_read'); k = first(r, lambda e: e['name'] == 'HandleReadIndexResponse')
r[k]['event']['state']['readStates'][0]['index'] = 3; save('m3_forwarded_resp_index', r); notes.append(f'm3_forwarded_resp_index: record {k+1} follower ReadState index -> 3')
r = load('stale_ack_reuse'); ks = [k for k, x in enumerate(r) if x['event']['name'] == 'ClientReadIndex']; k = ks[1]
r[k]['event']['state']['pending'][0]['from'] = 's2'; save('m4_stale_ack_requester', r); notes.append(f'm4_stale_ack_requester: record {k+1} pending.from -> s2')
r = load('stale_ack_reuse'); r[k]['event']['state']['pending'][0]['index'] = 3; save('m5_stale_ack_index', r); notes.append(f'm5_stale_ack_index: record {k+1} pending.index -> 3')
open(os.path.join(M, 'MUTANTS.md'), 'w').write('# Negative controls (hand-mutated copies of fresh traces; NOT implementation traces)\n\n' + '\n'.join('- ' + n for n in notes) + '\n')
print('\n'.join(notes))
