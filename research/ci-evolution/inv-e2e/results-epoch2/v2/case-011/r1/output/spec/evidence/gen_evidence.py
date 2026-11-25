#!/usr/bin/env python3
"""Generate and evaluate divergence-evidence states/transitions with TLC.

Each evidence item is a fixed pre-state S0 and either (a) no step (state
properties only), (b) one reference Action applied to S0, or (c) a fixed
constructed successor S1. Old definitions come from OldBase.tla (the prior
suite's base.tla, MODULE line renamed). Output: <id>/<id>.tla, .cfg, tlc.log.
"""
import os, subprocess, sys, json, re, shutil
HERE = os.path.dirname(os.path.abspath(__file__))
CP = "/work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar"
STATE_ROOT = "/dev/shm/specula-e2e-case-011/evidence"

VARS = ["role","vote","durableVote","votePersistPending","replyPending","replyMessage",
 "sendVotePending","leaseValid","candidateActive","candidateVote","candidateConfig","grants",
 "sentVoteReq","leaderActive","leaderVote","leaderCertified","leaderConfig","leaderGrants",
 "lastLog","durableLastLog","logFlushPending","committedConfig","committedConfigIndex",
 "effectiveConfig","effectiveConfigIndex","durableConfig","durableConfigIndex","messages",
 "crashed","seenGreaterLog","preCandidateActive","preCandidateVote","preCandidateConfig",
 "preGrants","preRoundFromLeader","faultCounters"]
DEFAULT = {
 "role": '[i \\in Server |-> "Follower"]',
 "vote": '[i \\in Server |-> DefaultVote(i)]',
 "durableVote": '[i \\in Server |-> DefaultVote(i)]',
 "votePersistPending": '[i \\in Server |-> FALSE]',
 "replyPending": '[i \\in Server |-> FALSE]',
 "replyMessage": '[i \\in Server |-> NoMessage]',
 "sendVotePending": '[i \\in Server |-> FALSE]',
 "leaseValid": '[i \\in Server |-> FALSE]',
 "candidateActive": '[i \\in Server |-> FALSE]',
 "candidateVote": '[i \\in Server |-> DefaultVote(i)]',
 "candidateConfig": '[i \\in Server |-> <<InitialConfig>>]',
 "grants": '[i \\in Server |-> {}]',
 "sentVoteReq": '[i \\in Server |-> {}]',
 "leaderActive": '[i \\in Server |-> FALSE]',
 "leaderVote": '[i \\in Server |-> DefaultVote(i)]',
 "leaderCertified": '[i \\in Server |-> FALSE]',
 "leaderConfig": '[i \\in Server |-> <<InitialConfig>>]',
 "leaderGrants": '[i \\in Server |-> {}]',
 "lastLog": '[i \\in Server |-> NoLog(i)]',
 "durableLastLog": '[i \\in Server |-> NoLog(i)]',
 "logFlushPending": '[i \\in Server |-> FALSE]',
 "committedConfig": '[i \\in Server |-> <<InitialConfig>>]',
 "committedConfigIndex": '[i \\in Server |-> 0]',
 "effectiveConfig": '[i \\in Server |-> <<InitialConfig>>]',
 "effectiveConfigIndex": '[i \\in Server |-> 0]',
 "durableConfig": '[i \\in Server |-> <<InitialConfig>>]',
 "durableConfigIndex": '[i \\in Server |-> 0]',
 "messages": '{}',
 "crashed": '[i \\in Server |-> FALSE]',
 "seenGreaterLog": '[i \\in Server |-> FALSE]',
 "preCandidateActive": '[i \\in Server |-> FALSE]',
 "preCandidateVote": '[i \\in Server |-> DefaultVote(i)]',
 "preCandidateConfig": '[i \\in Server |-> <<InitialConfig>>]',
 "preGrants": '[i \\in Server |-> {}]',
 "preRoundFromLeader": '[i \\in Server |-> FALSE]',
 "faultCounters": '[election |-> 0, membership |-> 0, crash |-> 0, drop |-> 0, preVote |-> 0]',
}
OLD_VARS = VARS[:30]

def over(var, mapping):
    """Per-node override on top of the default function."""
    parts = " @@ ".join('("%s" :> %s)' % (k, v) for k, v in mapping.items())
    return "(%s) @@ %s" % (parts, DEFAULT[var])

def state(**kw):
    s = dict(DEFAULT)
    for k, v in kw.items():
        s[k] = over(k, v) if isinstance(v, dict) else v
    return s

def assign(s, primed=False):
    p = "'" if primed else ""
    return "\n".join("    /\\ %s%s = %s" % (v, p, s[v]) for v in VARS)

STATE_PROPS = ["LeaderObjectVoteNotBehind", "TypeOK","VoteRequestAfterDurable","GrantedResponseAfterDurable",
  "LeaderRoleHasCommittedSelfVote","CandidateRoleHasPendingSelfVote",
  "CertifiedLeaderHasFrozenQuorum","NoForgedMessageEndpoints","DurableVoteNotAhead"]
STEP_PROPS = ["PreVoteRoundNotOutlivedByOwnLeadershipStep","PreVoteElectionByVoterStep",
  "PreVoteElectionAtProbedVoteStep","PreVoteRequestIsPureStep","PreVoteStartIsPureStep",
  "PreVoteGrantFromTrackedVoterStep"]

def module(eid, s0, step=None, s1=None):
    old_state = "<<" + ", ".join('"%s", V0!%s' % (p, p) for p in STATE_PROPS if p != "LeaderObjectVoteNotBehind") + ">>"
    new_state = "<<" + ", ".join('"%s", %s' % (p, p) for p in STATE_PROPS) + ">>"
    if s1 is not None:
        nxt = assign(s1, primed=True)
    elif step is not None:
        nxt = "    /\\ " + step
    else:
        nxt = "    /\\ UNCHANGED mcVars"
    steps = "<<" + ", ".join('"%s", %s' % (p, p) for p in STEP_PROPS) + ">>"
    return f"""---- MODULE {eid} ----
EXTENDS Update
\\* Old (V0) definitions over the same-named variables.
V0 == INSTANCE OldBase
EInit ==
{assign(s0)}
ENext ==
{nxt}
ESpec == EInit /\\ [][ENext]_mcVars
\\* Prints old and new verdicts of the state properties in every state.
ReportState == /\\ PrintT(<<"{eid}", "state", TLCGet("level"), "old", {old_state}>>)
               /\\ PrintT(<<"{eid}", "state", TLCGet("level"), "new", {new_state}>>)
\\* Prints the new verdicts of the update step predicates on every transition.
ReportStep == [][PrintT(<<"{eid}", "step", {steps}>>)]_mcVars
====
"""

CFG = """SPECIFICATION ESpec
CONSTANTS
    Server <- ReferenceServer
    NodeOrder <- ReferenceNodeOrder
    InitialConfig <- ReferenceInitialConfig
    MaxTerm = 3
    MaxLogIndex = 4
    PreVoteTickModes = {FALSE, TRUE}
    PreVoteRpcDefaultGrant = TRUE
    MaxElectionCount = 2
    MaxMembershipCount = 2
    MaxCrashCount = 1
    MaxDropCount = 1
    MaxMessageCount = 6
    MaxPreVoteCount = 2
INVARIANT ReportState
PROPERTY ReportStep
"""

def run(eid, s0, step=None, s1=None):
    d = os.path.join(HERE, eid); os.makedirs(d, exist_ok=True)
    open(os.path.join(d, eid + ".tla"), "w").write(module(eid, s0, step, s1))
    open(os.path.join(d, eid + ".cfg"), "w").write(CFG)
    for f in ["OldBase.tla"]:
        shutil.copy(os.path.join(HERE, f), d)
    for f in ["base.tla", "MC.tla", "Update.tla"]:
        shutil.copy(os.path.join(HERE, "..", f), d)
    meta = os.path.join(STATE_ROOT, eid)
    cmd = ["timeout", "120", "java", "-XX:+UseParallelGC", "-cp", CP, "tlc2.TLC", "-workers", "1",
           "-deadlock", "-metadir", meta, "-config", eid + ".cfg", eid]
    r = subprocess.run(cmd, cwd=d, capture_output=True, text=True)
    log = "COMMAND: (cd %s && %s)\n" % (d, " ".join(cmd)) + r.stdout + r.stderr
    open(os.path.join(d, "tlc.log"), "w").write(log)
    shutil.rmtree(meta, ignore_errors=True)
    for f in ["base.tla", "MC.tla", "Update.tla", "OldBase.tla"]:
        os.remove(os.path.join(d, f))
    lines = [l for l in log.splitlines() if l.startswith('<<"' + eid)]
    ok = "Model checking completed" in log or "No error" in log
    return ok, lines, log

V = lambda t, n, c: '[term |-> %d, node |-> "%s", committed |-> %s]' % (t, n, "TRUE" if c else "FALSE")
NL = lambda n: '[present |-> FALSE, term |-> 0, node |-> "%s", index |-> 0]' % n
LG = lambda t, n, x: '[present |-> TRUE, term |-> %d, node |-> "%s", index |-> %d]' % (t, n, x)
def MSG(kind, s, d, v, lg, gr, rv):
    return '[kind |-> "%s", source |-> "%s", dest |-> "%s", vote |-> %s, lastLog |-> %s, granted |-> %s, transfer |-> FALSE, reqVote |-> %s]' % (kind, s, d, v, lg, "TRUE" if gr else "FALSE", rv)
C123 = '<<{"1","2","3"}>>'

ITEMS = {}
# E-PREREQ: a Pre-Vote round just started by follower 1 (requests in flight, nothing persisted).
ITEMS["E_prereq"] = dict(s0=state(
    preCandidateActive={"1": "TRUE"}, preCandidateVote={"1": V(1, "1", 0)}, preGrants={"1": '{"1"}'},
    messages="{%s, %s}" % (MSG("PreVoteReq", "1", "2", V(1, "1", 0), NL("1"), 0, V(1, "1", 0)),
                           MSG("PreVoteReq", "1", "3", V(1, "1", 0), NL("1"), 0, V(1, "1", 0)))))
# Control for TypeOK: an unknown message kind must still be rejected.
ITEMS["E_typeok_ctrl"] = dict(s0=state(
    messages="{%s}" % MSG("Bogus", "1", "2", V(1, "1", 0), NL("1"), 0, V(1, "1", 0))))
# E-PREGRANT: a granted Pre-Vote response synthesized by the default RPC (vote = probe, never persisted).
ITEMS["E_pregrant"] = dict(s0=state(
    preCandidateActive={"1": "TRUE"}, preCandidateVote={"1": V(1, "1", 0)}, preGrants={"1": '{"1"}'},
    messages="{%s}" % MSG("PreVoteResp", "2", "1", V(1, "1", 0), NL("2"), 1, V(1, "1", 0))))
# U2 separating: established Leader 1 at (1,1,c) still holds a round (2,1) begun as Candidate.
U2 = dict(role={"1": '"Leader"'}, vote={"1": V(1, "1", 1), "2": V(1, "1", 0)},
    durableVote={"1": V(1, "1", 1), "2": V(1, "1", 0)},
    candidateVote={"1": V(1, "1", 0)}, grants={"1": '{"1","2"}'},
    leaderActive={"1": "TRUE"}, leaderVote={"1": V(1, "1", 1)}, leaderCertified={"1": "TRUE"},
    leaderConfig={"1": C123}, leaderGrants={"1": '{"1","2"}'},
    lastLog={"1": LG(1, "1", 1)}, durableLastLog={"1": LG(1, "1", 1)},
    preCandidateActive={"1": "TRUE"}, preCandidateVote={"1": V(2, "1", 0)}, preGrants={"1": '{"1"}'},
    preCandidateConfig={"1": C123},
    messages="{%s}" % MSG("PreVoteResp", "3", "1", V(0, "3", 0), NL("3"), 1, V(2, "1", 0)))
DELIVER = "\\E m \\in messages : Old!DeliverPreVoteResponse(m) /\\ UNCHANGED faultCounters"
ITEMS["E_u2_sep"] = dict(s0=state(**U2), step=DELIVER)
# U2 control: the same round on a follower (lease expired) elects without demoting a leader.
U2c = dict(vote={"1": V(1, "2", 1), "2": V(1, "2", 1)}, durableVote={"1": V(1, "2", 1), "2": V(1, "2", 1)},
    preCandidateActive={"1": "TRUE"}, preCandidateVote={"1": V(2, "1", 0)}, preGrants={"1": '{"1"}'},
    messages="{%s}" % MSG("PreVoteResp", "3", "1", V(0, "3", 0), NL("3"), 1, V(2, "1", 0)))
ITEMS["E_u2_ctrl"] = dict(s0=state(**U2c), step=DELIVER)
# U3 separating: Leader 1 removed from effective voters ({2,3}) holds a round it started as Leader.
U3 = dict(U2)
U3.update(effectiveConfig={"1": '<<{"2","3"}>>'}, committedConfig={"1": '<<{"1","2","3"},{"2","3"}>>'},
          committedConfigIndex={"1": "1"}, effectiveConfigIndex={"1": "2"}, lastLog={"1": LG(1, "1", 2)},
          preRoundFromLeader={"1": "TRUE"})
ITEMS["E_u3_sep"] = dict(s0=state(**U3), step=DELIVER)
# Probe mismatch separating (constructed, unreachable in the faithful model): round probe (3,1) but vote term 1.
U4 = dict(U2c); U4.update(preCandidateVote={"1": V(3, "1", 0)},
    messages="{%s}" % MSG("PreVoteResp", "3", "1", V(0, "3", 0), NL("3"), 1, V(3, "1", 0)))
ITEMS["E_probe_sep"] = dict(s0=state(**U4), step=DELIVER)
# Pure request handling: separating = constructed successor that adopts the requester's vote.
PRQ = MSG("PreVoteReq", "2", "1", V(1, "2", 0), NL("2"), 0, V(1, "2", 0))
PRS = MSG("PreVoteResp", "1", "2", V(0, "1", 0), NL("1"), 1, V(1, "2", 0))
PRSv = MSG("PreVoteResp", "1", "2", V(1, "2", 0), NL("1"), 1, V(1, "2", 0))
ITEMS["E_purereq_sep"] = dict(s0=state(messages="{%s}" % PRQ),
    s1=state(vote={"1": V(1, "2", 0)}, messages="{%s}" % PRSv))
ITEMS["E_purereq_ctrl"] = dict(s0=state(messages="{%s}" % PRQ),
    step="\\E m \\in messages : Old!DeliverPreVoteRequest(m) /\\ UNCHANGED faultCounters")
# Pure round start: separating = constructed successor that bumps the term while sending requests.
REQS = "{%s, %s}" % (MSG("PreVoteReq", "1", "2", V(1, "1", 0), NL("1"), 0, V(1, "1", 0)),
                    MSG("PreVoteReq", "1", "3", V(1, "1", 0), NL("1"), 0, V(1, "1", 0)))
ITEMS["E_purestart_sep"] = dict(s0=state(), s1=state(vote={"1": V(1, "1", 0)},
    preCandidateActive={"1": "TRUE"}, preCandidateVote={"1": V(1, "1", 0)}, preGrants={"1": '{"1"}'},
    messages=REQS, faultCounters='[election |-> 0, membership |-> 0, crash |-> 0, drop |-> 0, preVote |-> 1]'))
ITEMS["E_purestart_ctrl"] = dict(s0=state(), step='MCExternalPreElect("1")')
# Untracked grant: round frozen on {1,2}; a granted response from 3 is counted (code: expect() panic).
G = dict(preCandidateActive={"1": "TRUE"}, preCandidateVote={"1": V(1, "1", 0)}, preGrants={"1": '{"1"}'},
         preCandidateConfig={"1": '<<{"1","2"}>>'}, effectiveConfig={"1": '<<{"1","2"}>>'},
         committedConfig={"1": '<<{"1","2"}>>'},
         messages="{%s}" % MSG("PreVoteResp", "3", "1", V(0, "3", 0), NL("3"), 1, V(1, "1", 0)))
ITEMS["E_untracked_sep"] = dict(s0=state(**G), step=DELIVER)
Gc = dict(G); Gc["messages"] = "{%s}" % MSG("PreVoteResp", "2", "1", V(0, "2", 0), NL("2"), 1, V(1, "1", 0))
ITEMS["E_untracked_ctrl"] = dict(s0=state(**Gc), step=DELIVER)

if __name__ == "__main__":
    sel = sys.argv[1:] or list(ITEMS)
    summary = {}
    for eid in sel:
        it = ITEMS[eid]
        ok, lines, log = run(eid, it["s0"], it.get("step"), it.get("s1"))
        summary[eid] = {"tlc_completed": ok, "report": lines}
        print("==", eid, "completed" if ok else "NOT COMPLETED")
        for l in lines: print("  ", l)
        if not ok: print(log[-2000:])
    json.dump(summary, open(os.path.join(HERE, "evidence-results.json"), "w"), indent=1)
