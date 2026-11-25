# Modeling brief coverage (update revision, run `incr-705b7bab5f0d`)

Prior V0 coverage table is superseded by this file; V0 limits that still apply
are restated under "Honest limits".

## Scenario coverage

| Scenario | Base/MC/Update actions | Enabled configuration(s) | Fresh implementation evidence |
|---|---|---|---|
| S1 election persistence & dispatch (V0) | `DoElectCore`, `PersistVote`, `SendVoteRequest`, `FinishVoteBroadcast` | `MC.cfg`, `MC-membership.cfg`, `Update_full*.cfg` | `start_election`, `candidate_prevote_establish` (PersistVote/SendVoteRequest/FinishVoteBroadcast events) |
| S2 vote-request guards (V0) | `HandleVoteRequest` (+ R1 absent-log repair) | all MC cfgs | `reject_stale_log`, `grant_greater_vote`, `grant_vote_empty_logs` |
| S3 frozen joint quorum (V0) | `HandleVoteResponse`, `IsQuorum` | all MC cfgs | `establish_leader`, `candidate_prevote_establish` (real frozen quorum captured) |
| S4 establishment & contact (V0) | `HandleVoteResponse` (+ R2 lease), `SendAppendEntries`, `HandleAppendEntries` | all MC cfgs | `candidate_prevote_establish`, `prevote_new_round_same_leader_id` |
| S5 crash/restart (V0) | `Crash`, `Restart` (+ pre-candidate cleared) | `MC.cfg`, `MC_hunt_prevote_crash.cfg` | `restart_follower` |
| U-A round survives establishment | `TickElect`/`ExternalPreElect`→`PreElect`, `HandleVoteResponse`, `HandlePreVoteResponse` | `Update_full.cfg`→cex, `MC_hunt_leader_abdication.cfg` | `candidate_prevote_establish`; repro MC-2 |
| U-B round correlation | `PreElect` (ghost `preRound`), `HandlePreVoteResponse` (`SameLeaderId`) | `Update_full.cfg`→cex, `MC_hunt_stale_round.cfg` | `prevote_new_round_same_leader_id`; repro MC-1 |
| U-C stale grant from removed voter | membership actions + `HandlePreVoteResponse` panic branch | `MC_hunt_prevote_panic.cfg`, `Update_open.cfg` | `prevote_stale_member_panic`; repro MC-1 |
| U-D side-effect freedom under faults | `HandlePreVoteRequest`, `PreElect`, `Crash`, `DropMessage`, `ExpireLease` | `Update_full_cont2.cfg`, `Update_focused*.cfg`, `MC_hunt_prevote_crash.cfg` | `prevote_req_*`, `prevote_elect_multi`, `prevote_reject_greater_log` |
| U-E consumers cancel a round | `HandleVoteRequest`, `HandleAppendEntries`, `HandleVoteResponse` (adopt), `RefreshServerState`, `Restart`, `DoElectCore` | all Update cfgs; canary `CanaryNoPreCandidateDroppedByFollowing` | `prevote_cleared_by_vote_request`, `prevote_new_round_same_leader_id` |

## Property wiring

| Property | Defined | Enabled in |
|---|---|---|
| `TypeOK`/`MCTypeOK`/`TraceTypeOK` | base/MC/Trace | all cfgs |
| `DurableVoteNotAhead`, `DurableLogNotAhead`, `LeaderRoleHasCommittedSelfVote`, `CandidateRoleHasPendingSelfVote`, `CertifiedLeaderHasFrozenQuorum`, `MembershipAtMostOneOutstanding`, `NoForgedMessageEndpoints` | base | `base.cfg`, `MC.cfg`, `MC-membership.cfg`, `Trace.cfg`, all `Update_*`/`MC_hunt_*` cfgs (control) |
| `VoteRequestAfterDurable`, `GrantedResponseAfterDurable` | base | MC and Update cfgs |
| `PreVoteResponderSideEffectFree`, `PreVoteRequesterSideEffectFree`, `PreVoteElectionAtPreVotedTerm` | UpdateProps/Update | `Update_full*.cfg`, `Update_focused*.cfg`, `Update_open*.cfg`, hunts |
| `PreVoteStaleResponseIgnored` | UpdateProps/Update | `Update_full.cfg` (violated → MC-1), `MC_hunt_stale_round.cfg`, `Update_focused.cfg`, `Update_open.cfg` |
| `TimerPreVoteElectionFromFollowerState` | UpdateProps/Update | `Update_full.cfg`/`_cont1` (violated → MC-2), `MC_hunt_leader_abdication.cfg` |
| `PreVoteResponseNeverPanics`, `PreCandidateTracksNextTerm` | Update | all Update cfgs and hunts |
| `DischargeContext`, `FocusPartitionComplete` | Update | `Update_discharge*.cfg` |
| `TraceConsumed` | Trace | `Trace.cfg`, `EvidenceTrace.cfg` |
| Canaries (8) | Update | `Canary_*.cfg` (all violated = reachable) |

Continuation cfgs (`*_cont*.cfg`) disable only properties whose counterexamples
are already saved, so BFS keeps exploring the others.

## Non-vacuity evidence

- 21/21 fresh traces fully consumed (`TraceConsumed`), 20/20 field mutants rejected.
- Canaries violated: certified leader (3 voters), Pre-Vote election, Pre-Vote
  tally without quorum, lease rejection of a Pre-Vote, greater-log rejection,
  pre-candidate dropped by `become_following`, Leader holding a timer round,
  same-leader-id new round with an earlier response in flight
  (`spec/output/canary-*.log`).
- Regression mutants detected by U1, U2, U3, U7 (`spec/evidence/mutants/summary.txt`).

## Honest limits (LIMITED_COVERAGE)

- Three-node universe; `MaxTerm` 2 (3 in traces), `MaxLogIndex` 4; bounded
  election/membership/crash/drop counters and message bag (see cfgs).
- BFS runs that hit their time budget did not exhaust the state space; they are
  budget-limited explorations (see `spec/output/campaigns.md`).
- Follower-side membership replication is not modeled (V0 abstraction kept);
  the U-C panic is reached through leader-side membership change. Leadership
  transfer's lease bypass is not propagated to messages (V0 limitation).
- Time is abstract: the model admits tick restarts and response delays that the
  implementation bounds by `election_timeout`/`ttl`; reachability of each
  finding was therefore confirmed in code (see confirmation files).
- No fairness / liveness claims.
