# Reachability and non-vacuity evidence

## Completed model-check run

TLC completed with 1,562,585 generated states, 286,148 distinct states, zero states left on the queue,
and depth 25. The following action coverage is copied from `model-check.log` (`states:invocations`):

| Action | Coverage |
|---|---:|
| `MCElect` | 23:40 |
| `MCPersistVote` | 5451:259732 |
| `MCSendVote` | 314:50680 |
| `MCVoteResponse` | 153:560 |
| `MCVoteRequest` | 21:159800 |
| `MCDataAppend` | 5801:6616 |
| `MCAddLearner` | 10492:12028 |
| `MCJoint` | 10498:12028 |
| `MCUniform` | 0:0 |
| `MCFollowerAppend` | 45:84232 |
| `MCSubmit` | 21796:136939 |
| `MCFlush` | 20312:121619 |
| `MCRespond` | 1038:222974 |
| `MCSaveCommit` | 17409:54460 |
| `MCApply` | 14575:40152 |
| `MCAck` | 55195:144648 |
| `MCStale` | 78500:116828 |
| `MCCrash` | 40666:98500 |
| `MCRestart` | 3858:40748 |

All 12 configured invariants were evaluated on all 286,148 reachable states. Coverage is finite and
does not imply proof.

## Real-trace reachability

The eight trace files contain 20 post-state observations from actual exact-old Engine test calls.
Together they reach election/candidate/leader state, incoming vote handling, follower append and I/O
commands, learner addition, joint configuration, joint-to-uniform configuration, partial quorum
replication and commit, and reconstructed startup state. The uniform trace supplies concrete
non-vacuity evidence for the sole transition not reached in the final bounded MC configuration.

The rollback/session guard is reached in bounded model checking (`MCStale` is nonzero) but does not
have a dedicated real callback trace because the harness boundary is the synchronous Engine, while
the session object that rejects stale responses lives in the excluded asynchronous Core integration
layer. This limitation is recorded rather than inferred away.
