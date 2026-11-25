#!/usr/bin/env python3
"""Build trace inventory + campaign summary from the run ledger (V1)."""
import json, hashlib, os, glob, re, collections
OUT='/work/current/.specula-output'
SPEC=OUT+'/spec'
runs=[json.loads(l) for l in open(SPEC+'/output/incremental/runs/ledger.ndjson')]
byid={}
for r in runs: byid[r['id']]=r   # last wins
def sha(p): return hashlib.sha256(open(p,'rb').read()).hexdigest()
SEL={'follower-snap':'Zab1_0Test#testNormalFollowerRun','follower-diff':'Zab1_0Test#testNormalFollowerRunWithDiff',
 'quorum-startup-mutation-shutdown':'QuorumPeerMainTest#testQuorum','leader-abandon-restart-recovery':'QuorumPeerMainTest#testEarlyLeaderAbandonment',
 'diff-sync-uptodate-failure':'DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog'}
def selector(n):
    if n in SEL: return SEL[n]
    if n.startswith('follower-diff-bigdiff'): return 'SpeculaNewLeaderAckOrderTest#testFirstAckAfterNewLeaderWithDiff (specula.diff.txns=1500)'
    if n.startswith('repro-u3'): return 'SpeculaU3ReproTest#testTxnAckBeforeNewLeaderAck'
    if n.startswith('follower-diff-bulk'): return 'SpeculaNewLeaderAckOrderTest#testFirstAckAfterNewLeaderWithDiff'
    if n.startswith('repro-u4'): return 'SpeculaU4ReproTest#testNoRestartAfterUptodateFailure'
    if n.startswith('repro-u1'): return 'SpeculaU1ReproTest#testNewLeaderAckBeforeDurableThenRestart'
    if n.startswith('control-diffsync'): return 'SpeculaDiffSyncControlTest#testUpdateScenarioWithLeaderWait'
    return None
inv=[]
for group,pattern,kind in [('fresh-conformance',OUT+'/traces/*.ndjson','new-version'),
                           ('fresh-fault-injected',OUT+'/traces/fault-injected-repro/*.ndjson','new-version (fault-injected reproduction)'),
                           ('observation-only',OUT+'/traces/observation-only/*.ndjson','new-version (observation only; txn ids exceed the replay domain)'),
                           ('archived-v0',OUT+'/traces/archived-v0/*.ndjson','old-version (V0, immutable copy)'),
                           ('negative',OUT+'/traces/negative/*.ndjson','mutated (negative check)')]:
    for p in sorted(glob.glob(pattern)):
        n=os.path.basename(p)[:-7]
        lines=open(p).read().splitlines()
        ev=collections.Counter(json.loads(l)['event']['name'] for l in lines)
        val=None
        for key in ['final-tv-'+n,'final-'+n,'final-archived-'+n]:
            if key in byid: val=byid[key]
        e={'group':group,'kind':kind,'path':os.path.relpath(p,OUT),'sha256':sha(p),'records':len(lines),
           'scenario':json.loads(lines[0])['scenario'] if lines else None,'test':selector(n),'event_counts':dict(ev)}
        if group=='fresh-conformance' or group=='archived-v0' or group=='negative':
            if val: e['validation']={'log':val['log'],'exit':val['exit'],'outcome':val['outcome'],'states':val['states']}
        if group=='fresh-conformance':
            e['harness_log']=f"spec/output/incremental/harness/{n}.log"
        if group=='fresh-fault-injected':
            e['disposition']='reproduction evidence only: injected SyncRequestProcessor input loss + unprobed process restart are not representable by the observational Trace model'
        if group=='observation-only':
            e['disposition']='1500-txn DIFF ordering observation (NewLeaderAckSent before any fsync); not replayed: txn counters exceed the Trace.cfg Txn domain'
        if group=='archived-v0':
            e['disposition']='superseded: V0 implementation/instrumentation lacks the V1 NEWLEADER-ACK probes; replay stops at the first V1-dependent event'
        inv.append(e)
json.dump(inv,open(SPEC+'/output/incremental/trace-inventory.json','w'),indent=1)
# campaign summary (latest record per id, MC runs only)
mc=[r for r in byid.values() if not r['id'].startswith(('tv','final-','neg','ev-','archived-','tv1','ev'))]
rows=[]
for r in sorted(mc,key=lambda r:r['started']):
    log=OUT+'/'+r['log']
    txt=open(log).read() if os.path.exists(log) else ''
    viol=re.findall(r'(?:Invariant|Action property|Temporal property) (\S+) (?:is|was) violated',txt)
    sim='-simulate' in txt.split('\n',1)[0]
    depth=re.findall(r'depth of the complete state graph search is (\d+)',txt)
    gen=re.findall(r'^([\d,]+) states generated, ([\d,]+) distinct states found, ([\d,]+) states left on queue',txt,re.M)
    simstates=re.findall(r'The number of states generated: (\d+)',txt)
    stopped='stopAfter' in txt.split('\n',1)[0]
    rows.append({'id':r['id'],'module':r['module'],'cfg':r['cfg'],'mode':'simulation' if sim else 'bfs','exit':r['exit'],'outcome':r['outcome'],
                 'violated':viol[:1],'distinct':gen[-1][1] if gen else None,'generated':gen[-1][0] if gen else (simstates[-1] if simstates else None),
                 'queue':gen[-1][2] if gen else None,'depth':depth[-1] if depth else None,'log':r['log'],'started':r['started'],'finished':r['finished']})
json.dump(rows,open(SPEC+'/output/incremental/campaign-summary.json','w'),indent=1)
with open(SPEC+'/output/incremental/campaign-summary.md','w') as f:
    f.write('# V1 model-checking campaign summary (generated from runs/ledger.ndjson)\n\n')
    f.write('Exit 12 = invariant/property violation (counterexample in log). Exit 0 with a nonzero queue (or a simulation) = stopped by its time budget: LIMITED_COVERAGE, not a pass. Exit 0 with queue 0 = the configured finite, depth-bounded (and, for MC-filtered, MC-2-filtered) space was exhausted: still finite-bound evidence, not a proof. `mc-standard-filtered-sim` ran with the round-1 filter (`FilterKnownU4Flushed`); `mc-standard-filtered2-bfs` with the final `FilterKnownU4`.\n\n')
    f.write('| id | module | cfg | mode | exit | violated | distinct | generated | queue | depth | log |\n|---|---|---|---|---|---|---|---|---|---|---|\n')
    for r in rows:
        f.write(f"| {r['id']} | {r['module']} | {r['cfg']} | {r['mode']} | {r['exit']} | {', '.join(r['violated']) or '-'} | {r['distinct'] or '-'} | {r['generated'] or '-'} | {r['queue'] or '-'} | {r['depth'] or '-'} | {r['log']} |\n")
print(len(inv),'traces;',len(rows),'mc runs')
