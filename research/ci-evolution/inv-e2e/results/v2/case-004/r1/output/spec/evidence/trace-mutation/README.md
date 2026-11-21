# Trace-field consumption controls (mutation tests)

Each file is a fresh RaftCore trace from `traces/` with exactly one field changed
(`mutate.py <src> <dst> <line> <json-path> <value>`), replayed with the same
`Trace.tla`/`Trace.cfg` by `spec/run_trace_validation.sh`. A FAIL shows that the field is
compared by an active Trace predicate (a parse-only or stub check would PASS).

| id | source trace / line | mutation | expected | observed |
|---|---|---|---|---|
| m1 | core-transfer-to-learner/transfer-n4-003 L2 (learner TransferLeader) | role Candidate -> Learner | FAIL | FAIL |
| m2 | same | candidate true -> false | FAIL | FAIL |
| m3 | core-transfer-to-learner/transfer-n2-001 L2 (non-target TransferLeader) | vote_term 1 -> 2 (stutter violated) | FAIL | FAIL |
| m4 | core-t14-transfer-leader/transfer-n3-002 L4 (winning VoteResponse) | leader true -> false | FAIL | FAIL |
| m5 | core-transfer-to-learner/transfer-n2-001 L3 (VoteRequest grant) | args.last_term 1 -> 0 (older last LogId, same index) | FAIL (full-LogId freshness repair consumed) | FAIL |
| m6 | core-transfer-to-learner/transfer-n4-003 L2 | accepted_kind vote -> log (accepted_index -1) | FAIL | FAIL |
| m7 | same | commands {SaveVote,SendVote} -> {SaveVote} | FAIL | FAIL |
| m8 | core-t14-transfer-leader/transfer-n2-003 L2 (vote != from) | args.to -> the node itself | PASS (vote guard dominates: still a no-op) | PASS |
| m9 | core-transfer-to-learner/transfer-n4-003 L2 | vote_term 2 -> 3 | FAIL | FAIL |
| m10 | core-transfer-to-learner/transfer-n2-001 L2 (vote == from) | args.to -> the node itself (model must elect) | FAIL | FAIL |
| m11 | core-transfer-to-learner/transfer-n4-003 L2 | args.from_term 1 -> 2 (mismatch -> model no-op) | FAIL | FAIL |
