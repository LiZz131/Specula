#!/usr/bin/env python3
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
R = json.load(open(os.path.join(HERE, "evidence-results.json")))
def val(eid, kind, defs, prop, level=None):
    for r in R[eid]["reports"]:
        if r["kind"] == kind and (kind == "step" or (r["defs"] == defs and (level is None or r["level"] == level))):
            if prop in r["values"]:
                v = r["values"][prop] == "TRUE"
                if kind == "step" and not v: return False
                if kind != "step": return v
    return True if kind == "step" else None
def st(eid): return "spec/evidence/%s/%s.tla" % (eid, eid)
def lg(eid): return "spec/evidence/%s/tlc.log" % eid
E = []
def ev(id_, prop, role, src, eid, how, old, new, oldtlc, newtlc, impl=None, req=None, cell=None, expected=None):
    d = {"id": id_, "property": prop, "role": role, "state_source": src, "state": st(eid), "how_populated": how,
         "old": {"claimed": old, "tlc": oldtlc}, "new": {"claimed": new, "tlc": newtlc}, "log": lg(eid)}
    if impl: d["impl_produces"] = impl
    if req: d["requirement"] = req
    if cell: d["cell"] = cell
    if expected is not None: d["expected"] = expected
    E.append(d)
# TypeOK (modify: representation + new kinds)
ev("E-TypeOK", "TypeOK", "separating", "constructed", "E_prereq",
   "follower 1 just ran pre_elect: PreVoteReq 1->2, 1->3 with probe (1,1); mirrors trace prevote_start",
   False, True, val("E_prereq","state","old","TypeOK"), val("E_prereq","state","new","TypeOK"),
   {"value":"yes","basis":"engine pre_elect emits SendPreVote (pre_elect_test.rs:61-66); fresh trace traces/prevote_start.ndjson"},
   {"value":"allowed","citations":["openraft/src/docs/protocol/pre_vote.md:30-33"]}, "weakening justified")
ev("E-TypeOK-c", "TypeOK", "control", "constructed", "E_typeok_ctrl", "unknown message kind Bogus",
   False, False, val("E_typeok_ctrl","state","old","TypeOK"), val("E_typeok_ctrl","state","new","TypeOK"), expected=False)
# Keeps
ev("E-VRAD", "VoteRequestAfterDurable", "keep", "constructed", "E_prereq",
   "in-flight PreVoteReq whose probe (1,1) exceeds the sender's durable vote (0,1)",
   True, True, val("E_prereq","state","old","VoteRequestAfterDurable"), val("E_prereq","state","new","VoteRequestAfterDurable"),
   {"value":"yes","basis":"pre_elect never queues SaveVote (pre_elect_test.rs:48-66)"},
   {"value":"allowed","citations":["openraft/src/docs/protocol/pre_vote.md:42-45","openraft/src/engine/command.rs:138-142"]})
ev("E-GRAD", "GrantedResponseAfterDurable", "keep", "constructed", "E_pregrant",
   "granted PreVoteResp synthesized by the default pre_vote RPC; its vote (the probe) is durable nowhere",
   True, True, val("E_pregrant","state","old","GrantedResponseAfterDurable"), val("E_pregrant","state","new","GrantedResponseAfterDurable"),
   {"value":"yes","basis":"openraft/src/network/v2/network.rs:158-161"},
   {"value":"allowed","citations":["openraft/src/network/v2/network.rs:148-151","openraft/src/docs/protocol/pre_vote.md:42-44"]})
for p, k in [("LeaderRoleHasCommittedSelfVote","E-LRCSV"),("CandidateRoleHasPendingSelfVote","E-CRPSV"),("CertifiedLeaderHasFrozenQuorum","E-CLFQ"),("NoForgedMessageEndpoints","E-NFME")]:
    eid = "E_u2_sep" if p != "NoForgedMessageEndpoints" else "E_prereq"
    lvl = 2 if eid == "E_u2_sep" else 1
    ev(k, p, "keep", "constructed", eid,
       ("post-state (level 2) after a stale Pre-Vote quorum demotes Leader 1: role Candidate, vote (2,1) uncommitted, Leader object and certificate retained"
        if eid == "E_u2_sep" else "Pre-Vote messages among Server"),
       True, True, val(eid,"state","old",p,lvl), val(eid,"state","new",p,lvl),
       {"value":"yes","basis":"trace traces/stale_prevote_after_win.ndjson (Validation 2)"},
       {"value":"allowed","citations":["openraft/src/docs/data/vote.md:60-65","openraft/src/proposer/candidate.rs:113"]})
# Adds (new update properties; old verdict: not checked)
adds = [
 ("PreVoteRoundNotOutlivedByOwnLeadership","E_u2_sep","E_u2_ctrl","established Leader 1 (1,1,c) keeps round (2,1) started as Candidate; granted PreVoteResp from 3 elects",
  {"value":"yes","basis":"trace traces/stale_prevote_after_win.ndjson event 5 (TLC-validated) and real-runtime test harness/repro/t13_specula_stale_prevote_repro.rs (spec/output/repro-MC-1-new.log)"},
  {"value":"forbidden","citations":["openraft/src/docs/protocol/pre_vote.md:3-6","openraft/src/docs/protocol/pre_vote.md:44-45","openraft/src/config/config.rs:402-404","tests/tests/elect/t12_pre_vote.rs:57"]}),
 ("PreVoteElectionByVoter","E_u3_sep","E_u2_ctrl","Leader 1 removed from effective voters ({2,3}) holds a round it began as Leader; granted response elects",
  {"value":"unknown","basis":"requires leader-side round plus self-removal; MC hunt MC_hunt_prevote_membership.cfg"},
  {"value":"unknown","citations":["openraft/src/engine/engine_impl.rs:656-658 (learner may lead)"]}),
 ("PreVoteElectionAtProbedVote","E_probe_sep","E_u2_ctrl","constructed inconsistent round: probe (3,1) while vote term is 1",
  {"value":"no","basis":"every vote change except same-term commit drops the round (vote_handler/mod.rs:154-162,234-249)"},
  {"value":"forbidden","citations":["openraft/src/docs/protocol/pre_vote.md:31-33","openraft/src/docs/protocol/pre_vote.md:47-49"]}),
 ("PreVoteRequestIsPure","E_purereq_sep","E_purereq_ctrl","constructed successor where the responder adopts the probe while answering",
  {"value":"no","basis":"handle_pre_vote_req_test.rs:91-109; traces prevote_req_*"},
  {"value":"forbidden","citations":["openraft/src/docs/protocol/pre_vote.md:42-44","openraft/src/raft/mod.rs:939-940"]}),
 ("PreVoteStartIsPure","E_purestart_sep","E_purestart_ctrl","constructed successor that bumps the term while sending Pre-Vote requests",
  {"value":"no","basis":"pre_elect_test.rs:34-67; trace prevote_start"},
  {"value":"forbidden","citations":["openraft/src/docs/protocol/pre_vote.md:44-45"]}),
 ("PreVoteGrantFromTrackedVoter","E_untracked_sep","E_untracked_ctrl","round frozen on {1,2}; a granted response from 3 (not tracked) is processed",
  {"value":"unknown","basis":"needs a same-term earlier round with different membership; candidate.rs:106-112 would panic"},
  {"value":"unknown","citations":["openraft/src/proposer/candidate.rs:106-112 (impl only)"]}),
]
entries = []
for prop, sep, ctrl, how, impl, req in adds:
    sid = "E-" + prop; cid = sid + "-c"
    cell = {"forbidden": "strengthening justified" if impl["value"] == "no" else ("bug candidate" if impl["value"]=="yes" else "unresolved"),
            "unknown": "unresolved"}[req["value"]]
    ev(sid, prop, "separating", "constructed", sep, how, None, False, None, val(sep,"step","new",prop+"Step"), impl, req, cell)
    ev(cid, prop, "control", "constructed", ctrl, "nearby legal step (follower round / responder unchanged / tracked grant)",
       None, True, None, val(ctrl,"step","new",prop+"Step"), expected=True)
    entries.append({"property": prop, "replaces": None, "decision": "add", "kind": "new",
        "affected_because": "new Pre-Vote mechanism (engine_impl.rs:291-322,406-447,512-554)",
        "initial_decision": "add", "changed_from_initial": False, "evidence_ids": [sid, cid],
        "ledger_status": req["value"] if req["value"] != "forbidden" else "requirement", "watch_touched": True})
for e in entries:
    if e["property"] in ("PreVoteElectionByVoter",): e["ledger_status"] = "unknown"
    if e["property"] == "PreVoteGrantFromTrackedVoter": e["ledger_status"] = "model-internal"
entries = [
 {"property":"TypeOK","replaces":"TypeOK","decision":"modify","kind":"representation+weakening",
  "affected_because":"new variables (pre_candidate) and message kinds/fields","initial_decision":"modify","changed_from_initial":False,
  "evidence_ids":["E-TypeOK","E-TypeOK-c"],"ledger_status":"model-internal","watch_touched":False},
 {"property":"VoteRequestAfterDurable","replaces":None,"decision":"keep","kind":"keep",
  "affected_because":"watch touched (do_elect, run_command SendVote) and new message kind PreVoteReq quantified by kind","initial_decision":"keep","changed_from_initial":False,
  "evidence_ids":["E-VRAD"],"ledger_status":"impl-abstraction","watch_touched":True},
 {"property":"GrantedResponseAfterDurable","replaces":None,"decision":"keep","kind":"keep",
  "affected_because":"new granted response kind PreVoteResp answered without vote I/O","initial_decision":"keep","changed_from_initial":False,
  "evidence_ids":["E-GRAD"],"ledger_status":"requirement","watch_touched":False},
 {"property":"LeaderRoleHasCommittedSelfVote","replaces":None,"decision":"keep","kind":"keep",
  "affected_because":"new elect() caller can run on a Leader","initial_decision":"keep","changed_from_initial":False,
  "evidence_ids":["E-LRCSV"],"ledger_status":"requirement","watch_touched":True},
 {"property":"CandidateRoleHasPendingSelfVote","replaces":None,"decision":"keep","kind":"keep",
  "affected_because":"watch Engine::do_elect changed; new elect() caller","initial_decision":"keep","changed_from_initial":False,
  "evidence_ids":["E-CRPSV"],"ledger_status":"requirement","watch_touched":True},
 {"property":"CertifiedLeaderHasFrozenQuorum","replaces":None,"decision":"keep","kind":"keep",
  "affected_because":"a second Candidate instance (pre_candidate) uses the same grant_by; leader certificate survives pre-vote elect","initial_decision":"keep","changed_from_initial":False,
  "evidence_ids":["E-CLFQ"],"ledger_status":"mixed (quorum-granted: requirement; frozen-config: impl-abstraction)","watch_touched":True},
 {"property":"NoForgedMessageEndpoints","replaces":None,"decision":"keep","kind":"keep",
  "affected_because":"quantifies over all messages; new kinds","initial_decision":"keep","changed_from_initial":False,
  "evidence_ids":["E-NFME"],"ledger_status":"model-internal","watch_touched":False},
] + entries
# Trace-sourced upgrades (evaluated on TLC-validated replays, spec/evidence/E_trace/).
def tev(id_, prop, role, trace, log, new_tlc, how, impl=None, req=None, cell=None, expected=None):
    d = {"id": id_, "property": prop, "role": role, "state_source": "trace",
         "state": "traces/%s.ndjson" % trace, "how_populated": how,
         "old": {"claimed": None, "tlc": None}, "new": {"claimed": new_tlc, "tlc": new_tlc},
         "log": "spec/evidence/E_trace/%s" % log}
    if impl: d["impl_produces"] = impl
    if req: d["requirement"] = req
    if cell: d["cell"] = cell
    if expected is not None: d["expected"] = expected
    E.append(d)
REQ_U2 = {"value":"forbidden","citations":["openraft/src/docs/protocol/pre_vote.md:3-6","openraft/src/docs/protocol/pre_vote.md:44-45","openraft/src/config/config.rs:402-404","tests/tests/elect/t12_pre_vote.rs:57"]}
IMPL_U2 = {"value":"yes","basis":"TLC-validated trace stale_prevote_after_win (event 5) + real-runtime repro (RaftCore panics at engine_impl.rs:977)"}
tev("E-PreVoteRoundNotOutlivedByOwnLeadership-T", "PreVoteRoundNotOutlivedByOwnLeadership", "separating",
    "stale_prevote_after_win", "tlc-action-stale_prevote_after_win.log", False,
    "replay transition of event 5 (HandlePreVoteResponse on Leader (2,1,c) holding round (3,1))", IMPL_U2, REQ_U2, "bug candidate")
tev("E-PreVoteRoundNotOutlivedByOwnLeadership-Tc", "PreVoteRoundNotOutlivedByOwnLeadership", "control",
    "prevote_resp_quorum_elect", "tlc-action-prevote_resp_quorum_elect.log", True,
    "follower round reaching quorum (event 2)", expected=True)
tev("E-LeaderObjectVoteNotBehind-T", "LeaderObjectVoteNotBehind", "separating",
    "stale_prevote_after_win", "tlc-stale_prevote_after_win.log", False,
    "post-state of event 5: Leader object (2,1,c) retained, local vote (3,1) uncommitted",
    IMPL_U2, {"value":"forbidden","citations":["openraft/src/engine/engine_impl.rs:976-981 (debug_assert stating the rule)","spec/output/repro-MC-1-new.log (RaftCore Fatal::Panicked)"]}, "bug candidate")
tev("E-LeaderObjectVoteNotBehind-Tc", "LeaderObjectVoteNotBehind", "control",
    "prevote_resp_quorum_elect", "tlc-prevote_resp_quorum_elect.log", True,
    "follower round reaching quorum; no Leader object", expected=True)
ev("E-LeaderObjectVoteNotBehind-C", "LeaderObjectVoteNotBehind", "separating", "constructed", "E_u2_sep",
   "level-2 post-state of the constructed U2 transition", None, False, None, val("E_u2_sep","state","new","LeaderObjectVoteNotBehind",2))
entries.append({"property":"LeaderObjectVoteNotBehind","replaces":None,"decision":"add","kind":"new",
    "affected_because":"new elect() caller (handle_pre_vote_resp) can run while a Leader object exists",
    "initial_decision":"add","changed_from_initial":False,
    "evidence_ids":["E-LeaderObjectVoteNotBehind-T","E-LeaderObjectVoteNotBehind-Tc","E-LeaderObjectVoteNotBehind-C"],
    "ledger_status":"mixed (assertion-stated contract)","watch_touched":True,
    "note":"added during Validation after the real-runtime observation; not part of the Generation-time initial set"})
for e in entries:
    if e["property"] == "PreVoteRoundNotOutlivedByOwnLeadership":
        e["evidence_ids"] += ["E-PreVoteRoundNotOutlivedByOwnLeadership-T","E-PreVoteRoundNotOutlivedByOwnLeadership-Tc"]
# Model-checking-sourced witnesses (the TLC run is the evaluation of the actual definition).
E.append({"id":"E-PreVoteRoundNotOutlivedByOwnLeadership-MC","property":"PreVoteRoundNotOutlivedByOwnLeadership","role":"separating",
  "state_source":"mc","state":"spec/output/MC-1_update_full_violation.out (states 13 -> 14)",
  "how_populated":"BFS from Init over full MCNext (Update_full.cfg)","old":{"claimed":None,"tlc":None},
  "new":{"claimed":False,"tlc":False},"log":"spec/output/MC-1_update_full_violation.out",
  "impl_produces":IMPL_U2,"requirement":REQ_U2,"cell":"bug candidate"})
E.append({"id":"E-LeaderObjectVoteNotBehind-MC","property":"LeaderObjectVoteNotBehind","role":"separating",
  "state_source":"mc","state":"spec/output/MC-1_leader_object_attribution.out (last state)",
  "how_populated":"BFS from Init with elections only through Pre-Vote (MC_hunt_prevote_leader_object.cfg)","old":{"claimed":None,"tlc":None},
  "new":{"claimed":False,"tlc":False},"log":"spec/output/MC-1_leader_object_attribution.out",
  "impl_produces":IMPL_U2,"requirement":{"value":"forbidden","citations":["openraft/src/engine/engine_impl.rs:976-981","spec/output/repro-MC-1-new.log"]},"cell":"bug candidate"})
for e in entries:
    if e["property"] == "PreVoteRoundNotOutlivedByOwnLeadership": e["evidence_ids"].append("E-PreVoteRoundNotOutlivedByOwnLeadership-MC")
    if e["property"] == "LeaderObjectVoteNotBehind": e["evidence_ids"].append("E-LeaderObjectVoteNotBehind-MC")
E.append({"id":"E-PreVoteElectionByVoter-MC1","property":"PreVoteElectionByVoter","role":"separating","state_source":"mc",
  "state":"spec/output/D-2_PreVoteElectionByVoter_membership.out (states 14 -> 15)",
  "how_populated":"BFS (MC_hunt_prevote_membership_filtered.cfg): stale round survives the Candidate's win (MC-1 root cause), Leader removes itself (joint -> uniform {3}), stale grant elects a non-voter",
  "old":{"claimed":None,"tlc":None},"new":{"claimed":False,"tlc":False},"log":"spec/output/D-2_PreVoteElectionByVoter_membership.out",
  "impl_produces":{"value":"yes","basis":"same code path as MC-1 (engine_impl.rs:534-540 elects without a voter check); not separately run on the real runtime"},
  "requirement":{"value":"unknown","citations":["openraft/src/core/raft_core.rs:1971-1974 (impl guard only)","openraft/src/engine/engine_impl.rs:656-658 (a learner may lead)"]},"cell":"unresolved"})
E.append({"id":"E-PreVoteElectionByVoter-MC2","property":"PreVoteElectionByVoter","role":"separating","state_source":"mc",
  "state":"spec/output/D-2_PreVoteElectionByVoter_single_voter.out (last transition)",
  "how_populated":"BFS (MC_hunt_prevote_single_voter_filtered.cfg): operator elect(true) on the Leader passes the voter check, the Leader removes itself, the later quorum elects a non-voter",
  "old":{"claimed":None,"tlc":None},"new":{"claimed":False,"tlc":False},"log":"spec/output/D-2_PreVoteElectionByVoter_single_voter.out",
  "impl_produces":{"value":"yes","basis":"raft_core.rs:1683-1696 checks is_voter only when the round starts; engine_impl.rs:534-540"},
  "requirement":{"value":"unknown","citations":["openraft/src/core/raft_core.rs:1683-1696 (impl guard only)"]},"cell":"unresolved"})
for e in entries:
    if e["property"] == "PreVoteElectionByVoter": e["evidence_ids"] += ["E-PreVoteElectionByVoter-MC1","E-PreVoteElectionByVoter-MC2"]
E.append({"id":"E-PreVoteGrantFromTrackedVoter-MC","property":"PreVoteGrantFromTrackedVoter","role":"separating","state_source":"mc",
  "state":"spec/output/MC-2_cross_round_grant_violation.out (last transition)",
  "how_populated":"BFS (MC_hunt_prevote_membership_filtered.cfg) without crashes: round 1, node 2 removed, round 2 at the same probe, round-1 grant from node 2",
  "old":{"claimed":None,"tlc":None},"new":{"claimed":False,"tlc":False},"log":"spec/output/MC-2_cross_round_grant_violation.out",
  "impl_produces":{"value":"yes","basis":"harness/repro/t15_specula_cross_round_grant_repro.rs; spec/output/repro-D-4-new.log (panic at proposer/candidate.rs:107)"},
  "requirement":{"value":"forbidden","citations":["openraft/src/proposer/candidate.rs:106-112 (expect states the assumption; violation = RaftCore Fatal::Panicked)"]},"cell":"bug candidate"})
for e in entries:
    if e["property"] == "PreVoteGrantFromTrackedVoter":
        e["evidence_ids"].append("E-PreVoteGrantFromTrackedVoter-MC")
        e["note"] = "initial status model-internal/unknown; the code observation (panic) made the requirement explicit: an untracked grant crashes RaftCore"
for e in E:
    if e["id"] in ("E-TypeOK", "E-VRAD", "E-NFME"):
        e["state_source"] = "mc"
        e["how_populated"] += "; identical on every base variable to state 2 of spec/output/mc-canary-grant_response.log (reached from Init by MCTickPreVote(\"1\")); differs only in the MC counter faultCounters.preVote, which these predicates do not read"
doc = {"run": "case-011 pre-vote update", "generated_by": "spec/evidence/write_ledger.py",
       "evaluation_command": "python3 -I spec/evidence/gen_evidence.py && python3 -I spec/evidence/parse_evidence.py",
       "unaffected_properties": {"DurableVoteNotAhead":"watch symbols unchanged (config.rs change does not touch enable_leader_restore); Pre-Vote never writes vote",
                                  "DurableLogNotAhead":"no log path changed","MembershipAtMostOneOutstanding":"no membership path changed"},
       "entries": entries, "evidence": E, "bug_candidates": ["E-PreVoteRoundNotOutlivedByOwnLeadership","E-PreVoteRoundNotOutlivedByOwnLeadership-T","E-LeaderObjectVoteNotBehind-T","E-PreVoteGrantFromTrackedVoter-MC"],
       "unresolved": [{"property":"PreVoteElectionByVoter","missing_evidence":"non-implementation evidence that a non-voter must not start an election, or that it may"}]}
json.dump(doc, open(os.path.join(HERE, "..", "invariant-evidence.json"), "w"), indent=1)
bad = [e["id"] for e in E if e["new"]["claimed"] is not None and e["new"]["claimed"] != e["new"]["tlc"]] + \
      [e["id"] for e in E if e["old"]["claimed"] is not None and e["old"]["claimed"] != e["old"]["tlc"]]
print("claimed/TLC disagreements:", bad)
