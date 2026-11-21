# Modeling-brief coverage

| Brief item | Base action/state | Trace evidence | MC evidence | Status |
|---|---|---|---|---|
| S1 election | `StartElection`, `ReceiveVoteResponse`, candidate/grants | `election.ndjson` | candidate/leader reachability | covered |
| S2 vote request | `ReceiveVoteRequest`, ordered votes | `vote-request.ndjson` | vote monotonic/type invariants | covered |
| S3 follower append | `ReceiveAppendDirect`, I/O indices | `follower-append.ndjson` | append/flush/response actions | covered at Engine boundary |
| S4 partial replication | `AcknowledgeReplication`, match/commit | `partial-replication.ndjson` | partial-match and commit reachability | covered |
| S5 learner/joint/uniform change | `LeaderAppend` membership variants | three membership traces | learner/joint action coverage; uniform trace coverage | covered with bounded MC limitation |
| S6 rollback/session guard | `ReceiveAppend`, `DropStaleResponse` | state-independent stale-response invariant | stale session reachability | model checked; no dedicated real callback trace |
| S7 crash/restart | `Crash`, `Restart` | `restart.ndjson` startup boundary | crash/restart reachability | covered |
| FIFO command split | `commands`, I/O durability variables | exact Engine command arrays | I/O ordering invariants | covered |
| Snapshot/purge, payload, metrics | excluded | none | none | out of scope |

All required brief sections are represented. Per the experiment override, no target-specific hunt
configuration, known-bug campaign, bug report, reproduction, or historical annotation is part of
this frozen prior. `MC.cfg` is the ordinary neutral bounded exploration configuration.

Trace validation is necessary evidence of implementation conformance for the collected paths, not
coverage of every schedule. TLC exploration uses finite constants and action counters; any clean
result is recorded as `LIMITED_COVERAGE`, never proof.

## Update addendum (artifact d7176ef) — coverage of the update Scenarios

| Brief item | Base / MC action | Trace evidence | Update cfg(s) (properties enabled) | Status |
|---|---|---|---|---|
| U1 transfer to a voter | `TransferLeader`→`Elect`; `MCTransferLeader`, vote/append/ack framing | `core-t14-transfer-leader/*`, `core-transfer-all-nodes/*` | `Update_full.cfg`, `Update_full_controls.cfg`, `Update_focused.cfg`, `Update_open.cfg`, `Update_hunt_U1_voter_transfer.cfg` (CommittedLogAgreement, CandidateGrantSound, LeaderVoteCommitted, CurrentTermCommit, TypeOK, ElectionByVoterOnly, NoRaftCorePanic); canaries TransferElect / TransferLeaderWon / TransferCommit / OldLeaderStepsDown | covered (budget-limited) |
| U2 transfer to a non-voter | `TransferLeader`→`Elect` (learner branch), `CandidateGrantPanic` | `core-transfer-to-learner/transfer-n4-003` (+ code observation of the panic) | `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg`, `Update_hunt_U2_learner_transfer.cfg` (ElectionByVoterOnly), `Update_hunt_U2_panic.cfg` (NoRaftCorePanic), `Update_hunt_U2_learner_consequence.cfg` (controls); canaries LearnerCandidate / LearnerPanic / LearnerLeader | **violations found (MC-1)** |
| U3 stale `from` | `TransferLeader` else-branch | `core-t14-transfer-leader/transfer-n2-003`; mutation m8 | not enumerated in MC (stutter) | trace-validated |
| U4 crash/restart around the transfer | `Crash`, `Restart`, `MCCrash` | none (validation gap) | `Update_full*.cfg`, `Update_hunt_U1_voter_transfer.cfg` (CrashLimit 1); canary TransferCrash | MC only |
| Discharge of omitted context (MCApply, MCStale) | `EnvUpdate` | — | `Update_discharge.cfg` (`DischargeContext`) | see bug-report / changelog |

`ElectionByVoterOnly` and `NoRaftCorePanic` are defined in `Update.tla` and enabled in the
cfgs above (read from the files). The reference `MC.cfg` keeps the twelve V0 invariants.
