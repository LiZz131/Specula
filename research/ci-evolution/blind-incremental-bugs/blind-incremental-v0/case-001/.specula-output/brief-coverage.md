# Modeling brief coverage audit

## Scope rule

The binding V0 scope prohibits targeted hunt configurations and expected findings. All five brief scenarios are therefore merged into the neutral bounded `spec/MC.cfg`; this is intentional, not a missing per-scenario hunt file. Trace validation supplies concrete exact-old coverage for Scenarios 1-4. Scenario 5 is model-only because the neutral trace baseline did not request a crash schedule.

## Scenario coverage

| Brief scenario | Base/MC actions | Enabled configuration | Concrete trace evidence | Status |
|---|---|---|---|---|
| 1. Initialization and election sequencing | `EngineInitialize`, `EngineElect`, `SubmitAccepted`, `FlushSubmitted`, `DeliverLocalVoteResponse`, `SendVoteRequest` | `MC.cfg` | `initialization.ndjson`, `election.ndjson`, `io-lifecycle.ndjson` | covered within stated trace/model bounds |
| 2. Delayed vote response and establishment | `SendVoteRequest`, `DeliverVoteRequest`, `DeliverVoteResponse`, `DeliverLocalVoteResponse`, `BecomeLeader` | `MC.cfg` | `leader-establishment.ndjson` | covered within stated trace/model bounds |
| 3. Append, replication, commit | `LeaderAppend`, `SendAppendEntries`, `DeliverAppendEntries`, `AdvanceCommit` | `MC.cfg` | `append-replication.ndjson` | covered within stated trace/model bounds |
| 4. IO lifecycle | `IOAccept`, `IOSubmit`, `IOFlush`, `SubmitAccepted`, `FlushSubmitted` | `MC.cfg` | three-event `io-lifecycle.ndjson` | covered within stated trace/model bounds |
| 5. Crash/restart/message nondeterminism | `Crash`, `Restart`, `LoseMessage` plus message set | `MC.cfg` | none requested by neutral trace baseline | model-only, bounded coverage |

## Invariant wiring

| Brief invariant | Defined in | Wired through | Enabled in |
|---|---|---|---|
| `TypeOK` / `MCTypeOK` | `base.tla` / `MC.tla` | `MCSpec` state and counter domains | `MC.cfg`; `TypeOK` also in `Trace.cfg` |
| `IOOrdered` | `base.tla` | state invariant over IO identity pairs | `MC.cfg`, `Trace.cfg` |
| `CommittedWithinLog` | `base.tla` | state invariant | `MC.cfg`, `Trace.cfg` |
| `LeaderHasCommittedVote` | `base.tla` | state invariant | `MC.cfg`, `Trace.cfg` |
| `CandidateHasOwnVote` | `base.tla` | state invariant | `MC.cfg`, `Trace.cfg` |
| `MatchWithinLog` | `base.tla` | state invariant | `MC.cfg` |
| `ElectionSafety` | `base.tla` | state invariant | `MC.cfg` |
| `TraceMatched` | `Trace.tla` | temporal cursor completion | `Trace.cfg` property |

No proposed safety invariant is defined but disabled.

## Final bounded model reachability

Final ordinary bounds are two nodes, `MaxTerm = 2`, `MaxLog = 3`, at most two messages, two initialization attempts, one additional election, two vote sends, one leader append, one append send, one crash, and one message loss. These are environment/state-space bounds and therefore imply `LIMITED_COVERAGE`.

TLC completed the entire graph under those bounds: 1,111,399 generated states, 253,262 distinct states, zero states left on the queue, and depth 27. The preserved `-coverage 0` report shows nonzero successful evaluations for every `MCNext` branch:

| Action/branch | TLC coverage notation |
|---|---:|
| `MCInitialize` | `204:570` |
| `MCElect` | `6924:23134` |
| `MCSendVote` | `2057:5902` |
| `DeliverVoteRequest` | `3222:52478` |
| `DeliverVoteResponse` | `1692:114516` |
| `BecomeLeader` | `776:970` |
| `MCLeaderAppend` | `3461:19206` |
| `MCSendAppend` | `2120:6696` |
| `DeliverAppendEntries` | `4545:17952` |
| `SubmitAccepted` | `30363:185350` |
| `FlushSubmitted` | `27893:207418` |
| `DeliverLocalVoteResponse` | `5599:11788` |
| `AdvanceCommit` | `25441:96012` |
| `MCCrash` | `66906:97542` |
| `Restart` | `52873:96902` |
| `LoseMessage` | `19185:174962` |

The invariant predicates were evaluated over all 253,262 distinct bounded states. TLC reported no error. This is non-vacuity evidence for the configured scenarios and properties, not a proof beyond the bounds.

## Trace reachability and completion

| Trace | Events | Mapped action(s) | Complete TLC states/depth | Result |
|---|---:|---|---:|---|
| `initialization.ndjson` | 1 | `EngineInitializeLogged` | 2 / 2 | fully consumed |
| `election.ndjson` | 1 | `EngineElectLogged` | 2 / 2 | fully consumed |
| `leader-establishment.ndjson` | 1 | `HandleVoteResponseLogged` | 2 / 2 | fully consumed |
| `append-replication.ndjson` | 1 | `EngineAppendEntriesLogged` | 2 / 2 | fully consumed |
| `io-lifecycle.ndjson` | 3 | `IOAcceptLogged`, `IOSubmitLogged`, `IOFlushLogged` | 4 / 4 | fully consumed |

All seven fresh implementation events were accepted by their named actions, matched on the complete captured post-state, and advanced the replay cursor past end-of-file. `TraceMatched` completed with no TLC error for all five files.

## Explicit gaps

- Traces do not dynamically exercise vote/append rejection, message loss, or crash/restart.
- Traces use exact-old numeric `UTConfig`; arbitrary application-defined node ID encodings are outside this harness.
- The model collapses log contents to prefix lengths and peer acknowledgements to match cursors.
- The model has finite terms, logs, messages, and action counters.
- The earlier wide three-node iteration reached key election, leader, append, IO, commit, crash/restart, and loss branches but timed out with a nonempty queue. Its log is retained only as iteration evidence; final status relies on the completed bounded model and remains `LIMITED_COVERAGE`.
