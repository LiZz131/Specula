import re,sys,json,os
# usage: mkeval.py <id> <tlc.log> <state|last> '<json list of [label, expr]>' [<state2> for action pairs]
eid, log, which, evals = sys.argv[1], sys.argv[2], sys.argv[3], json.loads(sys.argv[4])
which2 = sys.argv[5] if len(sys.argv) > 5 else None
txt=open(log).read()
blocks=re.findall(r'State (\d+): <([^>]*)>\n(.*?)(?=\nState \d+: |\n\n|\Z)', txt, re.S)
def get(n):
    if n=='last': b=blocks[-1]
    elif n=='prev': b=blocks[-2]
    else: b=[x for x in blocks if x[0]==n][0]
    vs={}
    for mm in re.finditer(r'^/\\ (\w+) = (.*?)(?=\n/\\ |\Z)', b[2], re.S|re.M):
        vs[mm.group(1)]=' '.join(mm.group(2).split())
    return b[0], b[1].split(' line')[0], vs
VARS=["running","role","phase","syncMode","leaderOf","acceptedEpoch","currentEpoch","epochProposal","electionRound","votedFor","electionVotes","epochAcks","newLeaderAcks","newLeaderReady","syncComplete","learnerStage","dbCleared","prepared","syncQueued","leakedQueued","pending","durable","recoveryVisible","committed","applied","globalCommitted","acks","durabilityEvidence","commitWitness","nextTxn","snapshotBusy","snapshotImage","snapshotPublished"]
n1,a1,v1=get(which)
lines=[f"---- MODULE {eid} ----", "EXTENDS UpdateProps, TLC", "CONSTANTS s1, s2, s3", "Old == INSTANCE OldBase", f"\\* source: {log} state {n1} (reached by {a1})"]
lines.append("S0 == [" + ",\n       ".join(f"{k} |-> {v1[k]}" for k in VARS) + "]")
if which2:
    n2,a2,v2=get(which2)
    lines.append(f"\\* successor: state {n2} (reached by {a2})")
    lines.append("S1 == [" + ",\n       ".join(f"{k} |-> {v2[k]}" for k in VARS) + "]")
lines.append("EInit ==")
lines += [f"    /\\ {k} = S0.{k}" for k in VARS]
if not which2:
    lines.append("    /\\ PrintT(<<\"" + eid + "\", " + ", ".join(f"<<\"{lab}\", {ex}>>" for lab,ex in evals) + ">>)")
    lines.append("ENext == UNCHANGED vars")
else:
    lines.append("ENext == /\\ " + " /\\ ".join(f"{k}' = S1.{k}" for k in VARS))
    lines.append("         /\\ PrintT(<<\"" + eid + "\", " + ", ".join(f"<<\"{lab}\", {ex}>>" for lab,ex in evals) + ">>)")
lines.append("ESpec == EInit /\\ [][ENext]_vars")
lines.append("====")
os.makedirs(eid, exist_ok=True)
open(f"{eid}/{eid}.tla","w").write("\n".join(lines)+"\n")
cfg=f"""CONSTANTS
    s1 = s1
    s2 = s2
    s3 = s3
    Server = {{s1, s2, s3}}
    MaxEpoch = 2
    MaxTxn = 2
    NoServer = NoServer
    LearnerShutdownSemantics = "UPDATED"
INIT EInit
NEXT ENext
CHECK_DEADLOCK FALSE
"""
open(f"{eid}/{eid}.cfg","w").write(cfg)
print("wrote", eid)
