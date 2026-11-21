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
