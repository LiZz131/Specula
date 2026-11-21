# Modeling-brief coverage (updated for d7176ef9)

| Brief item | Base action/state | Trace evidence (fresh) | MC evidence | Status |
|---|---|---|---|---|
| S1 election | `Elect`, `StartElection`, `ReceiveVoteResponse` | `election.ndjson`, t14 windows | standard MC, canaries | covered |
| S2 vote request (full LogId) | `ReceiveVoteRequest`, `RejectVoteRequest` | `vote-request*.ndjson`, vote-request windows | standard MC | covered |
| S3 follower append | `ReceiveAppend` (real entries) | `follower-append.ndjson`, `follower-membership.ndjson` | standard MC | covered at Engine boundary |
| S4 partial replication / commit | `AcknowledgeReplication` via real responses | `partial-replication.ndjson` | standard MC, `CanaryTransferLeaderCommits` | covered |
| S5 learner/joint/uniform | `LeaderAppend`, follower membership effect | membership traces | standard MC (MembershipLimit=1: joint only), `Update_hunt_U1_absent*.cfg` (joint -> uniform) | covered with bounds |
| S6 rollback/session | `DropStaleResponse` only | none | omitted context (EnvUpdate + discharge) | follower truncation not modeled (recorded limit) |
| S7 crash/restart | `Crash`, `Restart`, `RestartFromRecovered` | `restart.ndjson` | standard MC, `Update_hunt_U4_crash.cfg`, `CanaryCrashBeforeSaveVote` | covered with bounds |
| U1 non-voter transfer target | `HandleTransferLeader`, `Elect`, `CoreVoteResponsePanic` | `elect-learner`, `elect-absent`, t99 windows incl. real panic | `Update_full*.cfg`, `Update_hunt_U1_absent_nodsb.cfg`, canaries NonVoterCandidate/AbsentElect | covered; finding MC-1 |
| U2 stale `from` | `TransferLeaderIgnored` | t14 `transfer-ignored-n1` | (no-op branch, not in MC) | trace-validated |
| U3 voter transfer + commit | `TransferLeaderElect`, network repairs | t14 windows | `Update_full_voter.cfg`, `Update_focused_voter.cfg`, `Update_open_voter.cfg`, canaries, `Update_hunt_U3_voter.cfg` | covered with bounds |
| U4 crash around transfer | `Crash` interaction | none (gap) | `Update_hunt_U4_crash.cfg` (BFS+sim), `CanaryCrashBeforeSaveVote` | MC only |
| Lease / metrics / timing | abstracted | none | none | excluded (time) |

Every update property is enabled in at least one cfg: `ElectionInitiatorIsVoter`,
`CandidateIsVoterOfSnapshot`, `NoCorePanic` (`Update_full*.cfg`, `Update_focused*.cfg`,
`Update_open.cfg`); `DischargeContext`, `PartitionComplete` (`Update_discharge.cfg`).
Any clean TLC result is recorded as `LIMITED_COVERAGE`, never proof.
