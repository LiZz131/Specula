# Trace field-consumption mutations

Each file is a fresh V1 trace with one field changed; Trace.tla must reject it.

- `m01_has_leader.ndjson`: Elect post.has_leader flipped
- `m02_progress_configs.ndjson`: Elect post.progress_configs changed
- `m03_vote_granted.ndjson`: HandleVoteResp post.vote_granted dropped 3
- `m04_vote_role.ndjson`: HandleVoteResp post.role changed
- `m05_up_committed.ndjson`: UpdateProgress post.committed not advanced
- `m06_up_progress_index.ndjson`: UpdateProgress post.progress[3].index changed
- `m07_up_progress_term.ndjson`: UpdateProgress post.progress[3].term changed
- `m08_up_arg_term.ndjson`: UpdateProgress args.term older->current (would commit)
- `m09_la_membership_pos.ndjson`: LeaderAppend args.membership_position removed
- `m10_la_progress_configs.ndjson`: LeaderAppend post.progress_configs not upgraded
- `m11_up_promotion.ndjson`: UpdateProgress post.committed_mem_index not promoted
- `m12_fc_committed.ndjson`: fast-commit-upto-membership post.committed = last
- `m13_fc_cm_index.ndjson`: fast-commit-upto-membership committed membership not promoted
- `m14_fna_promoted.ndjson`: follower no-advance post shows V0 promotion
- `m15_vp_committed.ndjson`: VecProgress unknown-id post_committed changed
