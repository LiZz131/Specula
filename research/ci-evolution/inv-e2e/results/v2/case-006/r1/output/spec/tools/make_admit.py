#!/usr/bin/env python3
"""Build a TLC path-admission check for a dumped counterexample.
usage: make_admit.py <cex.tla> <Name> <base cfg> <NextOp>
Writes spec/admit/<Name>Cex.tla (dump, renamed, with constant decls),
spec/admit/<Name>Admit.tla and .cfg.  The check starts in the dump's first
state and allows only steps that satisfy <NextOp> AND land exactly on the next
dumped state; reaching the last state violates AdmitNotDone (expected)."""
import sys, re, os
cex, name, basecfg, nextop = sys.argv[1:5]
spec = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(spec, 'admit'); os.makedirs(out, exist_ok=True)
txt = open(cex).read()
body = txt.split('\n', 1)[1]
mv = ['s1', 's2', 's3', 'ctx1', 'ctx2', 'v1']
open(f'{out}/{name}Cex.tla', 'w').write(f'---- MODULE {name}Cex ----\nCONSTANTS {", ".join(mv)}, Nil, Follower, Candidate, Leader, MsgVote, MsgVoteResp, MsgApp, MsgAppResp, MsgHeartbeat, MsgHeartbeatResp, MsgReadIndex, MsgReadIndexResp\n' + body)
varlist = ['term','vote','role','leader','logs','commitIndex','appliedIndex','durableTerm','durableVote','durableLogs','durableCommit',
           'matchIndex','nextIndex','votesGranted','recentActive','messages','pendingReads','readQueue','producedReads','publishedReads',
           'readyOutstanding','alive','leaderHistory','commitHistory','scenarioSeen','readStamp','servedReads','faultCounters']
eqs = lambda pfx, k: '\n'.join(f'    /\\ {v}{pfx} = Path[{k}].{v}' for v in varlist)
mod = f"""---- MODULE {name}Admit ----
EXTENDS Update
CONSTANTS {', '.join(mv)}
VARIABLE pc
D == INSTANCE {name}Cex
S == D!CounterExample.state
Path == [k \\in 1..Cardinality(S) |-> (CHOOSE p \\in S : p[1] = k)[2]]
AInit ==
    /\\ pc = 1
{eqs('', 1)}
ANext ==
    /\\ pc < Len(Path)
    /\\ {nextop}
{eqs("'", 'pc + 1')}
    /\\ pc' = pc + 1
ASpec == AInit /\\ [][ANext]_<<mcVars, pc>>
AdmitNotDone == pc < Len(Path)
====
"""
open(f'{out}/{name}Admit.tla', 'w').write(mod)
cfg = open(basecfg).read()
cfg = re.sub(r'SPECIFICATION \w+', 'SPECIFICATION ASpec', cfg)
cfg = re.sub(r'\nCONSTRAINT[^\n]*|\nSYMMETRY[^\n]*|\nVIEW[^\n]*', '', cfg)
cfg = re.sub(r'INVARIANTS[\s\S]*?(\n\n|$)', 'INVARIANTS\n    AdmitNotDone\n\n', cfg)
cfg = re.sub(r'PROPERTIES[\s\S]*$', '', cfg)
cfg = cfg.replace('CHECK_DEADLOCK FALSE', 'CHECK_DEADLOCK TRUE')
cfg = cfg.replace('CONSTANTS\n', 'CONSTANTS\n' + ''.join(f'    {m} = {m}\n' for m in mv), 1)
if 'ctx2' not in cfg.split('ReadContexts')[1].split('\n')[0]: pass
open(f'{out}/{name}Admit.cfg', 'w').write(cfg)
print(f'{out}/{name}Admit.tla')
