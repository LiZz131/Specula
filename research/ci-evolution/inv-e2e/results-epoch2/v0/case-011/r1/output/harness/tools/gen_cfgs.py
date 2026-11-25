#!/usr/bin/env python3
"""Generate Update/hunt/canary TLC configs for the Pre-Vote update suite."""
import sys, os
spec_dir = sys.argv[1]
OLD = ["MCTypeOK", "DurableVoteNotAhead", "DurableLogNotAhead", "VoteRequestAfterDurable",
       "GrantedResponseAfterDurable", "LeaderRoleHasCommittedSelfVote",
       "CandidateRoleHasPendingSelfVote", "CertifiedLeaderHasFrozenQuorum",
       "MembershipAtMostOneOutstanding", "NoForgedMessageEndpoints"]
UINV = ["PreVoteProbeIsNextTerm", "PreVoteTrackerWellFormed"]
ALLP = ["TickPreVoteNeverDeposesLeader", "PreVoteRequestIsReadOnly", "PreElectLeavesVoteUnchanged"]

def cfg(name, header, spec="MCSpec", init="<- ReferenceInitialConfig", setting="Runtime",
        maxterm=2, elect=2, prevote=2, memb=2, crash=1, drop=1, msgs=5, direct=True,
        extpre=True, props=(), invs=(), old=True):
    b = lambda x: "TRUE" if x else "FALSE"
    lines = [f"\\* {h}" for h in header.split("\n")]
    lines += [f"SPECIFICATION {spec}", "", "CONSTANTS",
              "    Server <- ReferenceServer", "    NodeOrder <- ReferenceNodeOrder",
              f"    InitialConfig {init}", f"    PreVoteSetting = \"{setting}\"",
              f"    MaxTerm = {maxterm}", "    MaxLogIndex = 4", "",
              f"    MaxElectionCount = {elect}", f"    MaxPreVoteCount = {prevote}",
              f"    MaxMembershipCount = {memb}", f"    MaxCrashCount = {crash}",
              f"    MaxDropCount = {drop}", f"    MaxMessageCount = {msgs}",
              f"    AllowDirectOperatorElect = {b(direct)}", f"    AllowExternalPreElect = {b(extpre)}",
              "", "CONSTRAINT MessageBound", "VIEW ModelView", "", "INVARIANTS"]
    lines += [f"    {x}" for x in ((OLD if old else ["MCTypeOK"]) + list(invs))]
    if props:
        lines += ["", "PROPERTIES"] + [f"    {x}" for x in props]
    with open(os.path.join(spec_dir, name), "w") as f:
        f.write("\n".join(lines) + "\n")

cfg("Update-full.cfg", "Update properties over the complete MCNext (Runtime pre-vote flag, all operator triggers).",
    props=ALLP, invs=UINV)
cfg("Update-full-noU2.cfg", "Follow-up of Update-full.cfg: the already-analyzed U2 property is disabled so\nexploration continues past its counterexample; every other property stays on.",
    props=ALLP[1:], invs=UINV)
cfg("Update-full-noU2-noMC2.cfg", "Follow-up of Update-full-noU2.cfg: PreVoteTrackerWellFormed (MC-2) is also disabled so\nexploration continues past both analyzed counterexamples; every other property stays on.",
    props=ALLP[1:], invs=["PreVoteProbeIsNextTerm"])
cfg("Update-full-enabled.cfg", "U1 over the complete MCNext: Pre-Vote enabled, no operator-forced direct election\n(Trigger::elect(false) and leadership transfer off); Trigger::elect(true) on.\nU2 (TickPreVoteNeverDeposesLeader) is disabled here: its counterexample is analyzed (MC-1).",
    setting="Enabled", direct=False, props=["SelfTermIncreaseNeedsPreVoteQuorum"] + ALLP[1:], invs=UINV)
cfg("Update-focused.cfg", "Concrete focused check: AffectedActions \\/ InteractionActions\n(membership append/commit and log flush omitted).",
    spec="FocusedSpec", props=ALLP, invs=UINV)
cfg("Update-open.cfg", "Open focused check: AffectedActions \\/ InteractionActions \\/ EnvUpdate\n(rely for omitted membership/flush context; see Update-discharge.cfg).",
    spec="OpenSpec", props=ALLP, invs=UINV)
cfg("Update-discharge.cfg", "Discharge: every omitted real context step of the full MCSpec satisfies EnvUpdate.",
    props=["DischargeContext"], invs=())
cfg("MC_hunt_prevote_leader.cfg", "Scenario U2 hunt: timer Pre-Vote rounds vs real election, leader establishment,\nand delayed responses. Pre-Vote enabled, no operator triggers, no membership change.",
    setting="Enabled", elect=1, prevote=3, memb=0, direct=False, extpre=False,
    props=["TickPreVoteNeverDeposesLeader", "SelfTermIncreaseNeedsPreVoteQuorum",
           "PreVoteRequestIsReadOnly", "PreElectLeavesVoteUnchanged"], invs=UINV)
cfg("MC_hunt_prevote_term.cfg", "Scenario U1/U3 hunt: term inflation, lease/log guards, external Pre-Vote trigger,\ncrash and loss, three terms. U2 property disabled (analyzed in MC_hunt_prevote_leader.cfg).",
    setting="Enabled", maxterm=3, elect=1, prevote=3, memb=1, crash=1, drop=2, msgs=6, direct=False,
    props=["SelfTermIncreaseNeedsPreVoteQuorum", "PreVoteRequestIsReadOnly", "PreElectLeavesVoteUnchanged"], invs=UINV)
cfg("MC_hunt_prevote_membership.cfg", "Scenario U5 hunt: single-voter seed grows to joint/uniform multi-voter configs;\nPre-Vote rounds freeze the effective config while membership evolves.\nU2 disabled (analyzed as MC-1).",
    init='= {"1"}', elect=1, prevote=2, memb=2, crash=1, drop=1, msgs=4,
    props=ALLP[1:], invs=UINV)
cfg("MC_hunt_prevote_stale_grant.cfg", "Scenario U5 hunt (three voters): repeated Pre-Vote rounds at one term across a membership change\n(operator Trigger::elect(true) on), checking that every counted grant belongs to the round's\nfrozen config (Candidate::grant_by panics otherwise). U2 disabled (analyzed as MC-1).",
    setting="Enabled", elect=1, prevote=3, memb=2, crash=0, drop=1, msgs=5, direct=False, extpre=True,
    props=ALLP[1:], invs=UINV)
cfg("MC_hunt_prevote_stale_grant_tight.cfg", "Scenario U5 follow-up of MC_hunt_prevote_stale_grant.cfg with unrelated faults removed\n(no drop) and a 4-message bound so BFS reaches the ~20-step leader-variant path.",
    setting="Enabled", elect=1, prevote=3, memb=2, crash=0, drop=0, msgs=4, direct=False, extpre=True,
    props=ALLP[1:], invs=UINV)
cfg("MC_hunt_prevote_restart.cfg", "Scenario U4 hunt: cancellation by following/do_elect and crash/restart of Pre-Vote\nstate, with two crashes and two drops. U2 property disabled (analyzed separately).",
    elect=1, prevote=2, memb=0, crash=2, drop=2, msgs=5,
    props=ALLP[1:], invs=UINV)
cfg("Canary-leader-tick-round.cfg", "Canary (expected violation): a cached Leader with a timer-started Pre-Vote round is reachable.",
    setting="Enabled", elect=1, prevote=3, memb=0, crash=0, drop=0, direct=False, extpre=False,
    invs=["CanaryNoLeaderWithTickPreRound"], old=False)
cfg("Canary-joint-round.cfg", "Canary (expected violation): a Pre-Vote round frozen on a joint config is reachable.",
    init='= {"1"}', elect=1, prevote=2, memb=2, crash=0, drop=0, msgs=4,
    invs=["CanaryNoJointPreVoteRound"], old=False)
cfg("Canary-rejected-resp.cfg", "Canary (expected violation): a rejected Pre-Vote response is reachable.",
    elect=1, prevote=2, memb=0, crash=0, drop=0, invs=["CanaryNoRejectedPreVoteResponse"], old=False)
for c in ["CanaryNoPreVoteElection", "CanaryNoLeaseRejectedPreVote", "CanaryNoPreVoteCancelledByFollowing",
          "CanaryNoGreaterLogFromPreVote", "CanaryNoPreVoteAfterRestart"]:
    cfg(f"Canary-{c[len('CanaryNo'):]}.cfg", f"Canary (expected violation) for {c}.",
        elect=1, prevote=2, memb=0, crash=1, drop=0, props=[c], old=False)
