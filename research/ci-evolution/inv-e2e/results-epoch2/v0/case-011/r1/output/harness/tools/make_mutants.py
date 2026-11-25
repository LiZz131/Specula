#!/usr/bin/env python3
"""Create single-field mutants of fresh traces; each mutant must FAIL replay.
Usage: make_mutants.py <traces_dir> <out_dir>"""
import json, sys, os, copy
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
def load(name): return [json.loads(l) for l in open(os.path.join(src, name + ".ndjson"))]
def bump(v): v = dict(v); v["term"] += 1; return v
M = [  # (mutant id, trace, event index, path, new value or callable)
 ("pre_elect.post.pre_candidate_active", "pre_elect", 0, ["post","pre_candidate_active"], False),
 ("pre_elect.post.pre_grants", "pre_elect", 0, ["post","pre_grants"], []),
 ("pre_elect.post.pre_candidate_vote", "pre_elect", 0, ["post","pre_candidate_vote"], bump),
 ("pre_elect.post.vote", "pre_elect", 0, ["post","vote"], bump),
 ("pre_elect.post.role", "pre_elect", 0, ["post","role"], "Candidate"),
 ("pre_elect.post.send_pre_vote_pending", "pre_elect", 0, ["post","send_pre_vote_pending"], False),
 ("pre_elect.post.save_vote_pending", "pre_elect", 0, ["post","save_vote_pending"], True),
 ("pre_elect.args.request_vote", "pre_elect", 0, ["args","request_vote"], bump),
 ("pre_elect.args.request_last_log", "pre_elect", 0, ["args","request_last_log","index"], 7),
 ("pre_elect.args.request_targets", "pre_elect", 0, ["args","request_targets"], ["2"]),
 ("pre_elect_single_voter.post.role", "pre_elect_single_voter", 0, ["post","role"], "Follower"),
 ("pre_vote_req_grant.args.response_granted", "pre_vote_req_grant", 0, ["args","response_granted"], False),
 ("pre_vote_req_grant.args.response_vote", "pre_vote_req_grant", 0, ["args","response_vote"], bump),
 ("pre_vote_req_grant.post.vote", "pre_vote_req_grant", 0, ["post","vote"], bump),
 ("pre_vote_req_lease_reject.args.response_granted", "pre_vote_req_lease_reject", 0, ["args","response_granted"], True),
 ("pre_vote_req_log_reject.args.response_granted", "pre_vote_req_log_reject", 0, ["args","response_granted"], True),
 ("pre_vote_req_vote_reject.args.response_granted", "pre_vote_req_vote_reject", 0, ["args","response_granted"], True),
 ("pre_vote_req_grant.args.response_last_log", "pre_vote_req_grant", 0, ["args","response_last_log","index"], 3),
 ("pre_vote_round.e2.post.seen_greater_log", "pre_vote_round", 1, ["post","seen_greater_log"], False),
 ("pre_vote_round.e2.post.pre_grants", "pre_vote_round", 1, ["post","pre_grants"], ["1","3"]),
 ("pre_vote_round.e3.post.role", "pre_vote_round", 2, ["post","role"], "Follower"),
 ("pre_vote_round.e3.post.pre_candidate_active", "pre_vote_round", 2, ["post","pre_candidate_active"], True),
 ("pre_vote_stale_resp.post.pre_candidate_active", "pre_vote_stale_resp", 0, ["post","pre_candidate_active"], True),
 ("vote_req_cancels_pre_vote.e2.post.pre_candidate_active", "vote_req_cancels_pre_vote", 1, ["post","pre_candidate_active"], True),
 ("elect_cancels_pre_vote.e2.post.pre_candidate_active", "elect_cancels_pre_vote", 1, ["post","pre_candidate_active"], True),
 ("candidate_pre_round_survives_leadership.e2.post.pre_candidate_active", "candidate_pre_round_survives_leadership", 1, ["post","pre_candidate_active"], False),
 ("candidate_pre_round_survives_leadership.e1.post.candidate_active", "candidate_pre_round_survives_leadership", 0, ["post","candidate_active"], False),
 ("leader_pre_vote_win.post.vote", "leader_pre_vote_win", 0, ["post","vote"], {"term": 2, "node": "1", "committed": True}),
 ("leader_pre_vote_win.post.role", "leader_pre_vote_win", 0, ["post","role"], "Leader"),
 ("restart_drops_pre_round.post.pre_candidate_active", "restart_drops_pre_round", 0, ["post","pre_candidate_active"], True),
 ("pre_vote_joint_config.e1.post.pre_candidate_config", "pre_vote_joint_config", 0, ["post","pre_candidate_config"], [["1","2","3"]]),
 ("pre_vote_joint_config.e2.post.role", "pre_vote_joint_config", 1, ["post","role"], "Candidate"),
 ("establish_leader.post.lease_valid", "establish_leader", 0, ["post","lease_valid"], False),
 ("start_election.post.candidate_config", "start_election", 0, ["post","candidate_config"], [["1","2"]]),
]
for mid, name, idx, path, val in M:
    recs = load(name)
    ev = recs[idx]["event"]
    cur = ev
    for k in path[:-1]: cur = cur[k]
    cur[path[-1]] = val(cur[path[-1]]) if callable(val) else val
    with open(os.path.join(out, mid + ".ndjson"), "w") as f:
        for r in recs: f.write(json.dumps(r) + "\n")
print(len(M))
