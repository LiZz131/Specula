# Modeling brief coverage (incremental Pre-Vote update)

The V0 audit is superseded where noted; numbers below are from this run
(`spec/output/campaign-summary.txt`, `spec/output/mc-*.log`). All
model-checking results are bounded (`LIMITED_COVERAGE`), never proofs.

## Update scenarios (modeling-brief.md §8)

| Scenario | Reference Actions | Update.tla focus | Enabled cfg(s) | Fresh trace evidence | Reachability witness | Outcome |
|---|---|---|---|---|---|---|
| U1 stale round × leader establishment | TickElect/ExternalPreElect→PreElect, HandleVoteResponse (win), PersistVote, HandlePreVoteRequest, HandlePreVoteResponse→DoElect | `PreVoteNeverDemotesEstablishedLeader`, diagnostic `PreVoteRoundNotInheritedByLeader` | `MC_hunt_prevote_leader.cfg`, `MC_hunt_prevote_leader_tickonly.cfg`, `MC_hunt_prevote_inherited_round.cfg`, `Update-full.cfg`, `Update-focused.cfg`, `Update-open.cfg` | `stale_pre_vote_after_establish` (5 events) | `Update-canary-preround-leader.cfg` (violated as expected) | **Violated → MC-1** (reproduced) |
| U2 probe/election agreement | PreElect, HandlePreVoteResponse, DoElect, every vote-changing Action | `PreVoteElectsAtProbedTerm`, invariant `PreCandidateProbesNextSelfTerm` | `Update-full-U2U4.cfg`, `Update-focused-U2U4.cfg`, `Update-open-U2U4.cfg`, `Update-full-rest.cfg`, `MC_hunt_prevote_membership.cfg`, `MC_hunt_prevote_crash.cfg` | `pre_vote_resp_quorum_elect`, `stale_pre_vote_after_establish` | `Update-canary-prevote-win.cfg` (violated as expected) | see bug-report.md table |
| U3 voter gate | HandlePreVoteResponse→DoElect, AppendJointConfig/AppendUniformConfig, RefreshServerState | `PreVoteElectOnlyByVoter` | `Update-full-rest.cfg`, `Update-full-prevote.cfg`, `MC_hunt_prevote_membership.cfg`, `Update-open-rest.cfg` | — (membership on a pre-candidate not traced) | `Update-canary-win-after-membership.cfg` (violated as expected) | **Violated → MC-2** (operator pre-vote on the leader + self-removal; reproduced) and via MC-1's inherited round |
| U4 pure query | HandlePreVoteRequest | `PreVoteHandlingIsSideEffectFree` (structural) | `Update-full-U2U4.cfg`, `Update-focused-U2U4.cfg`, `Update-open-U2U4.cfg`, `MC_hunt_prevote_crash.cfg` | `pre_vote_req_grant`, `..._reject_lease`, `..._reject_log`, `..._reject_vote` | `Update-canary-lease-reject.cfg` (violated as expected) | see bug-report.md table |
| U5 cancellation by contact / faults | HandleVoteRequest, HandleAppendEntries, HandleVoteResponse (adopt), RefreshServerState, Restart, Crash, DropMessage | `PreCandidateProbesNextSelfTerm`, U2 | `MC_hunt_prevote_crash.cfg`, all full/focused cfgs | `heartbeat_cancels_pre_vote`, `vote_grant_cancels_pre_vote` | `Update-canary-cancel-following.cfg` (violated as expected) | see bug-report.md table |

## Prior scenarios (V0 brief §2) on the updated reference

| Scenario | Actions | Enabled cfg | Fresh trace | Note |
|---|---|---|---|---|
| 1 Election persistence | StartElection/DoElect, PersistVote, SendVoteRequest | `MC.cfg`, `MC-membership.cfg` | `start_election` | |
| 2 Ordered vote guards | HandleVoteRequest | `MC.cfg` | `reject_stale_log`, `grant_greater_vote`, `vote_grant_cancels_pre_vote` | |
| 3 Frozen joint quorum | HandleVoteResponse, IsQuorum | `MC.cfg`, `MC-membership.cfg` | `establish_leader`, `pre_vote_resp_joint_no_quorum` (joint pre-vote tally) | prior 3-voter `MC.cfg` could not elect (NoLog defect); repaired |
| 4 Responses, establishment, contact | HandleVoteResponse, SendAppendEntries, HandleAppendEntries | `MC.cfg` | `establish_leader`, `heartbeat_cancels_pre_vote` | lease-on-establish repaired |
| 5 Crash/restart | Crash, Restart | `MC.cfg`, `MC_hunt_prevote_crash.cfg` | `restart_follower` | |

## Property wiring

| Property | Defined | Enabled in |
|---|---|---|
| `TypeOK`/`MCTypeOK`/`TraceTypeOK` | base/MC/Trace | all cfgs |
| `DurableVoteNotAhead`, `DurableLogNotAhead`, `LeaderRoleHasCommittedSelfVote`, `CandidateRoleHasPendingSelfVote`, `CertifiedLeaderHasFrozenQuorum`, `MembershipAtMostOneOutstanding`, `NoForgedMessageEndpoints` | base | `MC.cfg`, `MC-membership.cfg`, all `Update-full*`/focused/open/hunt cfgs, `Trace.cfg` |
| `VoteRequestAfterDurable`, `GrantedResponseAfterDurable` | base | `MC.cfg`, `MC-membership.cfg`, update cfgs |
| `PreVoteNeverDemotesEstablishedLeader` (U1) | Update | `Update-full.cfg`, `Update-focused.cfg`, `Update-open.cfg`, `MC_hunt_prevote_leader*.cfg` |
| `PreVoteElectsAtProbedTerm` (U2) | Update | `*-rest.cfg`, `*-U2U4.cfg`, `MC_hunt_prevote_membership.cfg`, `MC_hunt_prevote_crash.cfg` |
| `PreVoteElectOnlyByVoter` (U3) | Update | `*-rest.cfg`, `Update-full-prevote.cfg`, `MC_hunt_prevote_membership.cfg` |
| `PreVoteHandlingIsSideEffectFree` (U4) | Update | `*-rest.cfg`, `*-U2U4.cfg`, `MC_hunt_prevote_crash.cfg` |
| `PreCandidateProbesNextSelfTerm` | Update | all update full/focused/open cfgs, membership and crash hunts |
| `DischargeMembership` | Update | `Update-discharge.cfg`, `Update-discharge-seed1.cfg` |
| `TraceConsumed` | Trace | `Trace.cfg` |

`Update-full-prevote.cfg` now holds U2–U4 with Pre-Vote always on (the
filename is retained for the earlier plan).
