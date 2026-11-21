"""Generate TLC evidence modules (spec/evidence/<ID>/) from saved TLC states.

Each module EXTENDS Update, fixes one state (and optionally a successor),
prints old (V0 OldBase) and new property verdicts with PrintT, and is run
as a one/two-state behaviour (a static evaluation, not a campaign).
"""
import json, os, re, sys

SPEC = sys.argv[1]            # .../spec
CEX = sys.argv[2]             # TLC log with the counterexample states
OUT = os.path.join(SPEC, "evidence")

VARS = ["role", "vote", "durableVote", "votePersistPending", "replyPending", "replyMessage",
        "sendVotePending", "leaseValid", "candidateActive", "candidateVote", "candidateConfig",
        "grants", "sentVoteReq", "leaderActive", "leaderVote", "leaderCertified", "leaderConfig",
        "leaderGrants", "lastLog", "durableLastLog", "logFlushPending", "committedConfig",
        "committedConfigIndex", "effectiveConfig", "effectiveConfigIndex", "durableConfig",
        "durableConfigIndex", "messages", "crashed", "seenGreaterLog", "preCandidateActive",
        "preCandidateVote", "preCandidateLastLog", "preCandidateConfig", "preGrants",
        "sendPreVotePending", "preSentReq", "preStartRole", "faultCounters"]

def parse_states(path):
    txt = open(path).read()
    parts = re.split(r"\nState (\d+): [^\n]*\n", txt)
    states = {}
    for k in range(1, len(parts), 2):
        body = parts[k + 1].split("\n\n")[0]
        assigns = {}
        for m in re.finditer(r"/\\ (\w+) = (.*?)(?=\n/\\ |\Z)", body, re.S):
            assigns[m.group(1)] = " ".join(m.group(2).split())
        states[int(parts[k])] = assigns
    return states

def assign(state, primed=False):
    p = "'" if primed else ""
    return "\n".join("    /\\ %s%s = %s" % (v, p, state[v]) for v in VARS)

def module(eid, a, b, prints_init, prints_step):
    lines = ["---- MODULE %s ----" % eid, "EXTENDS Update", "OldV0 == INSTANCE OldBase", "",
             "EInit ==", assign(a)]
    for label, expr in prints_init:
        lines.append('    /\\ PrintT(<<"%s", "%s", %s>>)' % (eid, label, expr))
    if b is None:
        lines += ["", "ENext == FALSE"]
    else:
        lines += ["", "ENext ==", assign(a), assign(b, True)]
        for label, expr in prints_step:
            lines.append('    /\\ PrintT(<<"%s", "%s", %s>>)' % (eid, label, expr))
    lines += ["", "ESpec == EInit /\\ [][ENext]_mcVars", "===="]
    return "\n".join(lines) + "\n"

CFG = """SPECIFICATION ESpec
CONSTANTS
    Server <- ReferenceServer
    NodeOrder <- ReferenceNodeOrder
    InitialConfig <- ReferenceInitialConfig
    PreVoteSetting <- PreVoteAlwaysOn
    MaxTerm = 2
    MaxLogIndex = 4
    MaxElectionCount = 0
    MaxPreVoteCount = 2
    MaxMembershipCount = 0
    MaxCrashCount = 0
    MaxDropCount = 0
    MaxMessageCount = 5
"""

def with_var(state, var, expr):
    s = dict(state); s[var] = expr; return s

def main():
    st = parse_states(CEX)
    items = {}
    s3_bogus = with_var(st[3], "messages", st[3]["messages"].replace('"PreVoteReq"', '"Bogus"'))
    items["E1"] = (st[3], None, [("old.TypeOK", "OldV0!TypeOK"), ("new.TypeOK", "TypeOK")], [])
    items["E1c"] = (s3_bogus, None, [("new.TypeOK", "TypeOK")], [])
    items["E2"] = (st[3], None, [("old.VoteRequestAfterDurable", "OldV0!VoteRequestAfterDurable"),
                                 ("new.VoteRequestAfterDurable", "VoteRequestAfterDurable")], [])
    items["E3"] = (st[4], None, [("old.GrantedResponseAfterDurable", "OldV0!GrantedResponseAfterDurable"),
                                 ("new.GrantedResponseAfterDurable", "GrantedResponseAfterDurable")], [])
    items["E4"] = (st[2], None, [("old.CandidateRoleHasPendingSelfVote", "OldV0!CandidateRoleHasPendingSelfVote"),
                                 ("new.CandidateRoleHasPendingSelfVote", "CandidateRoleHasPendingSelfVote")], [])
    items["E4b"] = (st[16], None, [("old.CandidateRoleHasPendingSelfVote", "OldV0!CandidateRoleHasPendingSelfVote"),
                                   ("new.CandidateRoleHasPendingSelfVote", "CandidateRoleHasPendingSelfVote")], [])
    items["E5"] = (st[14], None, [("old.LeaderRoleHasCommittedSelfVote", "OldV0!LeaderRoleHasCommittedSelfVote"),
                                  ("new.LeaderRoleHasCommittedSelfVote", "LeaderRoleHasCommittedSelfVote")], [])
    items["E6"] = (st[4], None, [("old.NoForgedMessageEndpoints", "OldV0!NoForgedMessageEndpoints"),
                                 ("new.NoForgedMessageEndpoints", "NoForgedMessageEndpoints")], [])
    s7_bad = with_var(st[7], "preCandidateVote", st[7]["preCandidateVote"].replace(
        '"1" :> [term |-> 2, node |-> "1", committed |-> FALSE]', '"1" :> [term |-> 1, node |-> "1", committed |-> FALSE]'))
    items["E7"] = (s7_bad, None, [("new.PreCandidateVoteIsNextTerm", "PreCandidateVoteIsNextTerm")], [])
    items["E7c"] = (st[7], None, [("new.PreCandidateVoteIsNextTerm", "PreCandidateVoteIsNextTerm")], [])
    s5_bad = with_var(st[5], "vote", st[5]["vote"].replace(
        '"1" :> [term |-> 1, node |-> "1", committed |-> FALSE]', '"1" :> [term |-> 2, node |-> "1", committed |-> FALSE]'))
    items["E8"] = (st[4], s5_bad, [], [("new.PreVoteElectsProbedVoteStep", "PreVoteElectsProbedVoteStep")])
    items["E8c"] = (st[4], st[5], [], [("new.PreVoteElectsProbedVoteStep", "PreVoteElectsProbedVoteStep")])
    s4_bad = with_var(st[4], "vote", st[4]["vote"].replace(
        '"2" :> [term |-> 0, node |-> "2", committed |-> FALSE]', '"2" :> [term |-> 1, node |-> "1", committed |-> FALSE]'))
    items["E9"] = (st[3], s4_bad, [], [("new.PreVoteRequestPureStep", "PreVoteRequestPureStep")])
    items["E9c"] = (st[3], st[4], [], [("new.PreVoteRequestPureStep", "PreVoteRequestPureStep")])
    items["E10"] = (st[15], st[16], [], [("new.PreVoteNeverDemotesLeaderStep", "PreVoteNeverDemotesLeaderStep")])
    items["E10c"] = (st[4], st[5], [], [("new.PreVoteNeverDemotesLeaderStep", "PreVoteNeverDemotesLeaderStep")])
    items["E11"] = (st[14], None, [("new.NoStalePreCandidateAtLeader", "NoStalePreCandidateAtLeader")], [])
    items["E11c"] = (st[7], None, [("new.NoStalePreCandidateAtLeader", "NoStalePreCandidateAtLeader")], [])
    items["E12"] = (st[1], None, [("old.DurableLogNotAhead", "OldV0!DurableLogNotAhead"),
                                  ("new.DurableLogNotAhead", "DurableLogNotAhead")], [])
    # LogLE repair witness: two absent logs of different nodes (V0: not <=, V1: <=)
    items["E13"] = (st[3], None, [("old.LogLE(NoLog2,NoLog1)", 'OldV0!LogLE(lastLog["2"], lastLog["1"])'),
                                  ("new.LogLE(NoLog2,NoLog1)", 'LogLE(lastLog["2"], lastLog["1"])')], [])
    for eid, (a, b, pi, ps) in items.items():
        d = os.path.join(OUT, eid); os.makedirs(d, exist_ok=True)
        open(os.path.join(d, eid + ".tla"), "w").write(module(eid, a, b, pi, ps))
        open(os.path.join(d, eid + ".cfg"), "w").write(CFG)
    print(" ".join(items))

main()
