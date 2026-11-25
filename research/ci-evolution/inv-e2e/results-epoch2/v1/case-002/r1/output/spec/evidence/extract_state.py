#!/usr/bin/env python3
"""Extract state N from a TLC error-trace log and emit a one-state TLA+ evidence
module that evaluates the V0 (OldBase) and V1 (base/UpdateProps) properties."""
import re, sys
log, n, eid, kind = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]  # kind: trace|mc
txt = open(log).read()
m = re.search(r'^State %d: .*?\n(.*?)(?=^State \d+:|^\d+ states generated|\Z)' % n, txt, re.S | re.M)
if not m:
    sys.exit("state not found")
body = m.group(1)
drop = {'l', 'memStale', 'leaderBound', 'counters', 'seen'}
conj = []
for part in re.split(r'^/\\ ', body, flags=re.M):
    part = part.strip()
    if not part: continue
    name = part.split('=', 1)[0].strip()
    if name in drop: continue
    conj.append('/\\ ' + part)
init = '\n    '.join(c.replace('\n', '\n    ') for c in conj)
mod = f'''---- MODULE {eid} ----
EXTENDS UpdateProps
Old == INSTANCE OldBase
\\* Source: state {n} of {log.split('/spec/')[-1]} ({kind})
Init ==
    {init}
Next == UNCHANGED allVars
OldKept == <<Old!TypeOK, Old!ElectionSafety, Old!OneActiveLeaderPerEpoch,
             Old!CommittedHistoriesPrefix, Old!ApplyRequiresCommitCertificate,
             Old!PipelinePrefix, Old!EpochHistoryConsistency, Old!SyncCompletionJustified>>
NewKept == <<TypeOK, ElectionSafety, OneActiveLeaderPerEpoch,
             CommittedHistoriesPrefix, ApplyRequiresCommitCertificate,
             PipelinePrefix, EpochHistoryConsistency, SyncCompletionJustified>>
NewAdded == <<NewLeaderAckImpliesDurableSync, CertifiedDurableOnQuorum,
              CertifiedRetainedByLaterLeaders, NewLeaderAckIsFirstAck,
              VotingHistoryCoversDurable>>
EvalReport == PrintT(<<"{eid}", "old-kept", OldKept, "new-kept", NewKept, "new-added(P1..P5)", NewAdded>>)
====
'''
open(f'{eid}.tla', 'w').write(mod)
print(f'wrote {eid}.tla with {len(conj)} variables')
