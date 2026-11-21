# Exact-old Zab V0 modeling brief

## 1. System category and evidence boundary

This is a Category-A distributed replicated-state-machine model derived only
from `/work/source`. The modeled implementation has independently scheduled
election, learner, persistence, commit, and final-application paths. The source
identity and frozen scope are recorded in `provenance-manifest.json`. No later
revision, repository history, issue data, or external protocol description was
used.

## 2. Required scenarios

1. Ordinary three-voter startup and election: peers load stable storage, enter
   LOOKING, elect roles, exchange epoch support and epoch acknowledgements, and
   establish the leader. Evidence: `QuorumPeer.start/loadDataBase/run`
   (`QuorumPeer.java:768-824,1053-1145`), `FastLeaderElection.lookForLeader`
   (`FastLeaderElection.java:870-1080`), and `Leader.lead`
   (`Leader.java:417-527`).
2. Discovery and synchronization: accepted/current epochs have distinct
   in-memory and durable boundaries; the leader selects DIFF, TRUNC, or SNAP;
   the learner applies that choice before becoming broadcast-ready. Evidence:
   `Leader.getEpochToPropose/waitForEpochAck/waitForNewLeaderAck`
   (`Leader.java:1168-1351`), `Learner.registerWithLeader/syncWithLeader`
   (`Learner.java:287-531`), and `LearnerHandler.syncFollower`
   (`LearnerHandler.java:658-895`).
3. Broadcast pipeline: proposal receipt, request queueing, log append, force,
   acknowledgement, quorum commit, follower commit, and final application are
   separate transitions. Evidence: `Leader.propose/processAck/commit`
   (`Leader.java:808-990,1080-1129`), `Follower.processPacket`
   (`Follower.java:115-188`), `FollowerZooKeeperServer.logRequest/commit`
   (`FollowerZooKeeperServer.java:83-111`), `SyncRequestProcessor.run`
   (`SyncRequestProcessor.java:71-205`), and
   `FinalRequestProcessor.processRequest` (`FinalRequestProcessor.java:89-161`).
4. Crash and recovery: volatile/queued state is lost, while the transaction log
   and snapshot are stable inputs to restart and later synchronization.
   Evidence: `FileTxnSnapLog.restore` (`FileTxnSnapLog.java:175-245`),
   `ZKDatabase.loadDataBase` (`ZKDatabase.java:217-237`), and peer shutdown and
   restart paths (`QuorumPeer.java:768-824,1183-1224`).
5. Neutral harness scenario: start three voters, commit a mutation, stop one
   follower, commit two more mutations, restart/catch it up, stop all voters,
   restart all voters, verify recovered data, and commit a final mutation.

## 3. State and action mapping

The finite state in `spec/base.tla` tracks server availability and role;
leader association; accepted/current epochs and their durable copies; epoch,
NEWLEADER, and transaction acknowledgement sets; selected/applied sync mode;
queued, volatile, durable, committed, applied, and snapshot transaction sets;
global commits; broadcast readiness; and the last modeled action. `spec/MC.tla`
adds bounded start, client-proposal, and crash counters.

The action families are startup/election (`StartServer`, `ElectionDecision`),
discovery (`ReceiveEpochSupport` through `PersistCurrentEpoch`), synchronization
(`SelectSync` through `FollowerReady`), broadcast (`Propose` through
`ApplyTxn`), and failure (`Crash`). Each is cited directly in `base.tla` and in
`analysis-report.md`.

## 4. Documented abstractions

- Transaction identity is a finite ordered integer set. For model checking,
  compact zxids use `ModelTxnEpoch`; for traces, `modelZxid` is a lossless
  epoch/counter projection used only because TLC's JSON number path cannot
  preserve all native 64-bit zxids. Raw zxids remain in every event and in
  immutable original trace copies.
- Logs are sets over an ordered finite transaction domain. `PrefixClosed` and
  common-prefix invariants preserve the ordering facts needed by scope; byte
  serialization, TCP framing, and request payloads are excluded.
- `Observe` represents source markers whose state-changing boundary is already
  modeled elsewhere. It is never used to skip an input event: every event
  advances exactly one trace cursor position after field checks pass.
- A narrow silent pre-append proposal-receive action represents an old marker
  placement after `logRequest`: the independently scheduled sync processor can
  append before the caller obtains the trace-writer monitor. The later marker
  is still consumed and checked.
- The SNAP recovery exception in `PipelineOrdering` is explicit and temporary:
  the exact-old learner deserializes the snapshot before the subsequent
  `takeSnapshot` persistence boundary (`Learner.java:358-398`).

## 5. Safety properties

The canonical configurations check `TypeOK`, `EpochConsistency`,
`PipelineOrdering`, `GlobalCommitHasVotingDurability`,
`CommittedHistoriesArePrefixes`, `SingleReadyLeaderPerEpoch`,
`ServingEpochDurable`, and `AppliedWasGloballyCommitted`. Trace validation
checks the same property set plus the temporal `TraceMatched` condition.

## 6. Verification plan

### 6.1 Model checking

`base.cfg` is the canonical fault-free two-voter protocol exploration with one
transaction and one epoch. `MC.cfg` is the canonical bounded crash/restart
exploration; it is intentionally small enough to exhaust naturally. Both must
exit zero and print a final queue size of zero. Broader two-voter crash/client
runs are retained as open-frontier, resource-limited evidence and are not
reported as proofs.

### 6.2 Trace validation

`harness/validate-suite.sh` enumerates every top-level `traces/*.ndjson` file,
sets `JSON` to that file, and runs `Trace.tla`/`Trace.cfg` before either
canonical model. There is no scenario-name predicate. `TraceMatched` requires
the cursor to exceed the dynamically loaded trace length.

