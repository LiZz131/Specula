#!/usr/bin/env python3
"""Writes spec/invariant-evidence.json from the TLC evaluation results
(spec/evidence/evidence-results.json) and the MC witness results."""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__)); SPEC = os.path.dirname(HERE)
R = json.load(open(os.path.join(HERE, 'evidence-results.json')))
W = json.load(open(os.path.join(HERE, 'livelock-results.json'))) if os.path.exists(os.path.join(HERE, 'livelock-results.json')) else {}

def ev(eid, prop, role, src, how, old, new, impl, req, cell, expected=None):
    e = {"id": eid, "property": prop, "role": role, "state_source": src,
         "state": "spec/evidence/%s/E_%s.tla" % (eid, eid.replace('-', '_')),
         "how_populated": how, "log": "spec/evidence/%s/tlc.log" % eid,
         "tlc_output": R.get(eid, {}).get('prints')}
    if old is not None: e["old"] = old
    if new is not None: e["new"] = new
    if impl: e["impl_produces"] = impl
    if req: e["requirement"] = req
    if cell: e["cell"] = cell
    if expected is not None: e["expected"] = expected
    return e

entries = [
 {"property": "TypeOK", "replaces": "TypeOK (V0)", "decision": "modify", "kind": "representation-only (weakening for new message kinds/variables)",
  "affected_because": "new variables preActive/preVote/preConfig/preGrants/appendBehindVote and message kinds PreVoteReq/PreVoteResp with field round (engine_impl.rs:95-165,297-322)",
  "initial_decision": "modify", "changed_from_initial": False, "evidence_ids": ["E-TYPE", "E-TYPEc"]},
 {"property": "VoteRequestAfterDurable", "decision": "keep", "affected_because": "a new request kind (PreVoteReq) now exists whose vote is never persisted",
  "initial_decision": "keep", "changed_from_initial": False, "evidence_ids": ["E-VRAD"]},
 {"property": "GrantedResponseAfterDurable", "decision": "keep", "affected_because": "a new granted response kind (PreVoteResp) exists; its vote is the responder's unchanged vote",
  "initial_decision": "keep", "changed_from_initial": False, "evidence_ids": ["E-GRAD"]},
 {"property": "LeaderRoleHasCommittedSelfVote / CandidateRoleHasPendingSelfVote / DurableVoteNotAhead", "decision": "keep",
  "affected_because": "DoElect is now also reached from HandlePreVoteResponse, including on an established Leader (engine_impl.rs:536-539)",
  "initial_decision": "keep", "changed_from_initial": False, "evidence_ids": ["E-ROLE"]},
 {"property": "CertifiedLeaderHasFrozenQuorum", "decision": "keep (unaffected control)", "affected_because": "not affected; kept enabled in every update cfg as the unaffected core control",
  "initial_decision": "keep", "changed_from_initial": False, "evidence_ids": []},
 {"property": "PreCandidateProbesNextTerm", "replaces": None, "decision": "add", "kind": "strengthening (new structural/update property)",
  "affected_because": "elect() after a Pre-Vote quorum uses the current term (engine_impl.rs:536-539, 262-268), so the probed vote must still be term+1",
  "initial_decision": "add", "changed_from_initial": False, "evidence_ids": ["E-U1k", "E-U1s"]},
 {"property": "PreVoteQuorumNeverDemotesLeader", "replaces": None, "decision": "add", "kind": "strengthening (new interaction property)",
  "affected_because": "establish_leader -> become_leader keeps pre_candidate (engine_impl.rs:855-881, vote_handler/mod.rs:154-230); a later quorum calls elect() on the Leader",
  "initial_decision": "add", "changed_from_initial": False, "evidence_ids": ["E-U2s", "E-U2c"]},
 {"property": "NoPermanentPreVoteLivelock (+ LivelockClosed)", "replaces": None, "decision": "add", "kind": "new liveness requirement encoded as a safety witness plus closure",
  "affected_because": "Pre-Vote responses never adopt a higher vote and Pre-Vote requests never update the responder (engine_impl.rs:414-447,542-553), unlike real vote responses (engine_impl.rs:485-509)",
  "initial_decision": "add", "changed_from_initial": False, "evidence_ids": ["E-U3s", "E-U3c"]},
]
evidence = [
 ev("E-TYPE", "TypeOK", "separating", "trace", "post-state of event 1 (PreElect) in traces/prevote_quorum_elect.ndjson (TLC -dump state 2)",
    {"claimed": False, "tlc": False}, {"claimed": True, "tlc": True},
    {"value": "yes", "basis": "trace prevote_quorum_elect event 1 (real Engine::pre_elect emits SendPreVote)"},
    {"value": "allowed", "citations": ["openraft/src/engine/command.rs:138-142", "openraft/src/docs/protocol/pre_vote.md:28-33"]},
    "weakening justified"),
 ev("E-TYPEc", "TypeOK", "control", "trace", "E-TYPE state with one message kind replaced by \"Bogus\" (short edit)",
    None, {"claimed": False, "tlc": False}, None, None, None, expected=False),
 ev("E-VRAD", "VoteRequestAfterDurable", "keep", "trace", "same state as E-TYPE: PreVoteReq (2,1) in flight while durableVote[1] = (1,2,committed)",
    {"claimed": True, "tlc": True}, {"claimed": True, "tlc": True},
    {"value": "yes", "basis": "trace prevote_quorum_elect event 1"},
    {"value": "allowed", "citations": ["openraft/src/engine/command.rs:138-142 (SendPreVote does not persist a vote)", "openraft/src/docs/protocol/pre_vote.md:36-43"]},
    "keep correct: extending the property to PreVoteReq (TLC: extended=FALSE) would reject a legal state"),
 ev("E-GRAD", "GrantedResponseAfterDurable", "keep", "trace", "final state of traces/prevote_request_branches.ndjson (granted PreVoteResp in flight)",
    {"claimed": True, "tlc": True}, {"claimed": True, "tlc": True},
    {"value": "yes", "basis": "trace prevote_request_branches event 3"},
    {"value": "allowed", "citations": ["openraft/src/raft/mod.rs:936-943 (Pre-Vote never persists a vote)"]}, "keep correct"),
 ev("E-ROLE", "LeaderRoleHasCommittedSelfVote / CandidateRoleHasPendingSelfVote / DurableVoteNotAhead", "keep", "trace",
    "post-state of event 5 of traces/candidate_prevote_then_establish.ndjson (Pre-Vote quorum elected on a Leader)",
    {"claimed": True, "tlc": True}, {"claimed": True, "tlc": True},
    {"value": "yes", "basis": "trace candidate_prevote_then_establish"},
    {"value": "allowed", "citations": ["openraft/src/raft_state/mod.rs:416-440 (server state derived from vote)"]}, "keep correct"),
 ev("E-U1k", "PreCandidateProbesNextTerm", "keep", "trace", "pre-state of event 5 of candidate_prevote_then_establish (Leader (1,1,c) with live round (2,1))",
    {"claimed": "not checked", "tlc": "not checked"}, {"claimed": True, "tlc": True},
    {"value": "yes", "basis": "trace"}, {"value": "allowed", "citations": ["openraft/src/docs/protocol/pre_vote.md:28-33"]}, "added property accepts the observed state"),
 ev("E-U1s", "PreCandidateProbesNextTerm", "separating", "constructed", "E-U1k with vote[1] replaced by (2,3,uncommitted) while the round (2,1) survives",
    {"claimed": "not checked", "tlc": "not checked"}, {"claimed": False, "tlc": False},
    {"value": "no", "basis": "MC: PreCandidateProbesNextTerm enabled in every update cfg, never violated (see bug-report.md coverage)"},
    {"value": "forbidden", "citations": ["openraft/src/docs/protocol/pre_vote.md:47-49 (the real election follows the probe that a quorum answered)"]},
    "strengthening justified"),
 ev("E-U2s", "PreVoteQuorumNeverDemotesLeader", "separating", "trace",
    "events 4->5 of traces/candidate_prevote_then_establish.ndjson (TLC -dump states 25->26), the consumed PreVoteResp put back into the pre-state message set (short edit)",
    {"claimed": "not checked", "tlc": "not checked"}, {"claimed": False, "tlc": False},
    {"value": "yes", "basis": "real Engine run: trace candidate_prevote_then_establish event 5 (Leader -> Candidate at term 2)"},
    {"value": "forbidden", "citations": ["openraft/src/docs/protocol/pre_vote.md:3-6", "openraft/src/docs/protocol/pre_vote.md:13-24",
                                         "openraft/src/config/config.rs:397-404", "openraft/src/core/raft_core.rs:1966-1969"]},
    "bug candidate: keep the stronger property, record the defect (MC-2)"),
 ev("E-U2c", "PreVoteQuorumNeverDemotesLeader", "control", "trace", "E-U2s with the post-state keeping role Leader and vote (1,1,committed)",
    None, {"claimed": True, "tlc": True}, None, None, None, expected=True),
]
if W:
    evidence.append({"id": "E-U3s", "property": "NoPermanentPreVoteLivelock", "role": "separating", "state_source": "mc",
        "state": W.get("witness_module"), "how_populated": W.get("how"), "log": W.get("log"),
        "old": {"claimed": "not checked", "tlc": "not checked"}, "new": {"claimed": False, "tlc": False},
        "impl_produces": {"value": "yes (each step) / unknown (whole schedule)", "basis": W.get("impl_basis")},
        "requirement": {"value": "forbidden", "citations": ["tests/tests/elect/t12_pre_vote.rs:188-197", "openraft/src/docs/protocol/pre_vote.md:47-49"]},
        "cell": "bug candidate: keep the stronger property, record the defect (MC-1)",
        "closure": W.get("closure"), "old_behaviour_control": W.get("control_off")})
    evidence.append({"id": "E-U3c", "property": "NoPermanentPreVoteLivelock", "role": "control", "state_source": "mc",
        "state": W.get("witness_module"), "how_populated": "same witness state with the election tick in pre-update mode (TickPreVoteModes={FALSE})",
        "expected": "a leader is reachable", "log": W.get("control_log"), "tlc": W.get("control_off")})
doc = {"entries": entries, "evidence": evidence,
       "bug_candidates": ["E-U2s"] + (["E-U3s"] if W else []),
       "unresolved": [] if W else [{"property": "NoPermanentPreVoteLivelock", "missing_evidence": "MC witness pending"}]}
json.dump(doc, open(os.path.join(SPEC, 'invariant-evidence.json'), 'w'), indent=1)
print("written", len(entries), "entries", len(evidence), "evidence")
