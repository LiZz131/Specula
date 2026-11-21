# Exact-old V0 validation summary

## Result

All nine fresh implementation trace families match `TraceSpec`; all five final bounded safety runs (main plus four scenarios) completed with no invariant violation and empty queues. Because trace collection uses selected exact-old unit environments and model checking uses finite bounds, the suite result is **LIMITED_COVERAGE**, not proof.

No implementation-caused mismatch (Case C) was found. Intermediate failures were classified as trace-spec or model-spec mechanics and corrected without weakening a code-faithful property.

## Trace validation

The runnable harness regenerated 44 nonempty NDJSON events from `/work/work-source`:

| Trace | Events | Final TLC result |
|---|---:|---|
| election | 1 | matched; 2 distinct states |
| leader append | 1 | matched; 2 distinct states |
| leader membership append | 1 | matched; 2 distinct states |
| follower commit | 1 | matched; 2 distinct states |
| membership update | 1 | matched; 2 distinct states |
| progress | 8 | matched; 9 distinct states |
| quorum | 12 | matched; 13 distinct states |
| greatest majority | 11 | matched; 12 distinct states |
| replication lag | 8 | matched; 9 distinct states |

Final evidence is in `output/trace-*-final.log`. Every final run has exit status 0, reaches `l > Len(TraceLog)`, and reports no error. Trace.cfg also checks `TypeOK` and `MembershipOrder`; the isolated follower-commit fixture limitation is documented in `instrumentation-spec.md`.

## Model checking

| Run | Distinct states | Queue at finish | Result |
|---|---:|---:|---|
| `MC.cfg` | 12,831 | 0 | no error |
| scenario 1 progress/loss | 30,034 | 0 | no error |
| scenario 2 membership | 80,705 | 0 | no error |
| scenario 3 follower commit | 12,831 | 0 | no error |
| scenario 4 elections/crash | 30,606 | 0 | no error |

The main enables TypeOK, ElectionSafety, ActiveLeaderHasCommittedVote, CommitWithinLocalLog, CommittedLogAgreement, and MembershipOrder. Focused configurations additionally check CommitWitnessSound and OneOutstandingMembership. Action coverage is positive for election/grant, client append, semantic send/delivery/ack handling, membership proposal, message loss, and crash/recovery across the focused runs.

Three expected-failure reachability models establish non-vacuity: a leader, a commit witness, and an outstanding effective membership are each reached. Their logs are `output/mc-reach-{leader,commit,membership}-final.log`; the named `NotReach*` invariant violations are expected reachability witnesses, not safety findings.

The broad `MC_scale.cfg` run is intentionally reported separately. It reached 10,347,332 distinct states in 600 seconds without a reported invariant violation but timed out with 6,580,486 states queued. It is not treated as exhaustive or green.

## Coverage limitations

- Three model servers and small term/index/action budgets.
- Short exact-old unit scenarios, not a full storage/network cluster.
- Snapshot transfer, purge layout, timer precision, framing, and payload meaning remain outside the binding scope.
- Conflict rejection and negative-ack discard do not have positive action coverage in the converged tight models.

Accordingly, trace validation and model checking are both honest `LIMITED_COVERAGE` results.

---

# V1 validation handoff (updated revision)

- Source: `work-source/` = artifact commit `aa05a38` (`update`) + `harness/patches/instrumentation.patch` (sha256 prefix 0d15febd844b3c71). Old-revision control tree: `work-source-old/` at `ce863f4` (observation test only).
- Harness command: `bash harness/run.sh` (applies the patch, `cargo +stable test`, per-scenario `timeout 300s`, depth-0 preprocessing). Last run: `spec/output/upd-harness-run.log` (exit 0). Instrumented lib suite: 103/103 pass (`spec/output/upd-instrumented-lib-tests.log`); uninstrumented updated lib suite: 100/100 (`spec/output/new-lib-tests.log`).
- Fresh trace inventory (18 files, all nonempty, `traces/*.ndjson`): V0 regressions rerun: election, leader_append, follower_commit, membership_update, progress, quorum, replication_state. Update-focused: leader_fast_commit, leader_fast_commit_upto_membership, leader_fast_commit_membership_no_voter_change, leader_fast_commit_voter_change_to_1, update_progress, update_progress_no_leader, update_effective_membership_leader, update_effective_membership_to_learner, update_effective_membership_index0 (fixture cfg), leader_lifecycle (14-event chain: Elect -> HandleVoteResp -> LeaderAppend -> UpdateProgress x2 -> joint LeaderAppend -> UpdateProgress x2 -> uniform LeaderAppend -> UpdateProgress (untracked id) -> UpdateProgress -> HandleVoteResp(higher vote) -> Elect -> HandleVoteResp), follower_commit_no_advance.
- Archived V0 traces (`traces/v0-archived/`): retained as immutable old-version evidence; `leader_membership_append` and `greatest_majority` superseded (source drift), the other seven re-collected fresh.
- Affected-action coverage in fresh traces: StartElection (Elect), candidate vote counting (HandleVoteResp), LeaderAppendEntries incl. membership split (LeaderAppend), Engine::update_progress (UpdateProgress: no leader, untracked id, older-term quorum value, commit, promotion, joint quorum), update_effective_membership (leader and non-leader branches), follower promotion on advance / no advance (FollowerCommit), VecProgress unknown id (ProgressUpdate). Not directly traced (environment limitation, as in V0): HandleUpdateMatched / DeliverAppendEntries / RejectAppendConflict / GrantVote message-level actions, whose Engine cores (update_progress, follower_commit_entries, handle_vote_resp) are traced.
- Result: 17/17 Trace.cfg replays and the index0 Trace_fixture.cfg replay complete with `TraceMatched` and no invariant error. Semantic spec files were changed by Generation only; no validation repair changed base/MC semantics.

## V1 model checking (final suite)

Final spec file hashes (sha256 prefixes): base.tla e37a9f30a1b38a6e; MC.tla cced7d4691e82513; Update.tla e52ed4c0a4a91095; Trace.tla 5844ef9f7eb79132; Trace.cfg bfff98265c067e48; Trace_fixture.cfg ba3c7ac968ea9496; MC.cfg ed1931202c8431e6; Update_full.cfg d7ceb2f4d4cd0a2f; Update_focused.cfg 245483cb6d05e648; Update_open.cfg 0677606bf83aad09; Update_discharge.cfg 48816d9996f1048f; 

All runs below started after the last spec edit (base.tla 02:57:47 UTC), so their results apply to these files. TLC 2026.11.06; 3 servers; states under /dev/shm/specula-e2e-case-012/ (removed after every run); exact commands are on the first line of each log in spec/output/.

| Campaign | Result | Classification |
|---|---|---|
| Standard MC.cfg | 8,115 distinct, queue 0, depth 20, no error | exhaustive within V0 bounds |
| Full update (Update_full, MCNext) | BFS 24.7M distinct (queue 12.1M, depth 18) + simulation 32.4M states; no violation of the standard, update or structural properties or ProgressMonotonic | LIMITED_COVERAGE |
| Concrete focused (FocusedNext) | BFS 19.7M distinct (queue 10.7M) + simulation 26.5M; no violation | LIMITED_COVERAGE |
| Open focused (OpenNext with EnvUpdate) | BFS 20.3M distinct (queue 10.1M) + simulation 31.8M; no violation | LIMITED_COVERAGE (provisional on discharge) |
| Discharge (DischargeContext over MCNext) | BFS 15.9M distinct (queue 8.1M); no violation of the rely by Crash/Recover/LoseMessage/DiscardNegativeAck steps | LIMITED_COVERAGE |
| Inherited hunts S1-S4 | BFS exhaustive within bounds (17,130 / 55,571 / 8,115 / 30,606 distinct) + 30-min simulations (47-67M states each); no violation | bounded |
| Update hunts U-S1/U-S2/U-S3 | BFS 11.7M / 19.3M / 16.9M distinct (budget-limited) + simulations 26.3M / 39.2M / 38.7M; no violation | LIMITED_COVERAGE |
| V0 broad probe MC_scale.cfg | BFS 56.3M distinct (queue 33.1M, depth 17); no violation | LIMITED_COVERAGE |
| Reachability canaries | leader, commit witness, outstanding membership, U-S1 append-commit, U-S2 re-election with older witness, U-S4 progress upgrade, two leaders, two committed nodes: all reached; U-S3 covered-but-unpromoted probe not reached in 8.6M distinct states | non-vacuity |

The repair batch in changelog Round 2 invalidated the earlier provisional campaign results (moved to spec/output/superseded-prerepair/). The full fresh-trace regression was re-run on the repaired candidate (spec/output/trace-*-v1r3*.log). No spec edit followed the final campaigns, so no further rerun was required.

Overall V1 status: trace validation complete for all retained fresh traces; model checking without any implementation finding; **COMPLETED_WITH_LIMITED_COVERAGE** (bounded and budget-terminated exploration, untraced message-level actions, conflict/negative-ack branches not covered, OneOutstandingMembership excluded from crash configs).
