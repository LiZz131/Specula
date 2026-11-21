# Exact-old source analysis and validation repair report

## Evidence reviewed

Only the frozen scope, deterministic audit, pristine `/work/source`, its
writable instrumented copy `/work/work-source`, the supplied TLA+ libraries,
and the preceding V0 artifacts were inspected. The analysis followed control
and data flow through peer startup/election, leader discovery, learner sync,
proposal persistence/commit/application, and restart recovery.

## Source-derived boundaries

- `QuorumPeer.run` selects LOOKING/FOLLOWING/OBSERVING/LEADING loops independently
  (`QuorumPeer.java:1053-1145`). Election completion therefore changes role but
  does not atomically complete epoch discovery or synchronization.
- `Leader.getEpochToPropose` accumulates raw connecting ids and returns an
  already-selected epoch once `waitingForNewEpoch` is false
  (`Leader.java:1168-1199`). `waitForEpochAck` and `waitForNewLeaderAck` use
  separate sets and waits (`Leader.java:1201-1351`). The model retains those
  independent quorum phases.
- `QuorumPeer.setAcceptedEpoch` and `setCurrentEpoch` write separate epoch files
  (`QuorumPeer.java:1752-1767`). The model separates memory updates from durable
  copies, and serving readiness requires their agreement.
- `LearnerHandler.syncFollower` chooses DIFF/TRUNC/SNAP based on leader database
  bounds and the peer zxid (`LearnerHandler.java:658-895`).
  `Learner.syncWithLeader` receives transactions and applies the selected mode
  before NEWLEADER/UPTODATE completion (`Learner.java:344-531`).
- `Follower.processPacket(PROPOSAL)` decodes then calls
  `FollowerZooKeeperServer.logRequest` (`Follower.java:115-188`). That request is
  handled asynchronously by `SyncRequestProcessor`, which appends and batches
  force operations (`SyncRequestProcessor.java:71-205`); `SendAckRequestProcessor`
  then acknowledges (`SendAckRequestProcessor.java:40-57`). Queue, append,
  durable, and acknowledgement state are consequently distinct.
- The leader's proposal map and quorum acknowledgement precede `commit`
  (`Leader.java:808-990,1080-1129`). Follower commit and final application run
  through separate processors (`FollowerZooKeeperServer.java:97-111`,
  `CommitProcessor.java:381-449`, `FinalRequestProcessor.java:89-161`).
- Restore combines snapshot and transaction log data
  (`FileTxnSnapLog.java:175-245`, `ZKDatabase.java:217-237`). The model keeps
  stable restored records available for recovery while only globally justified
  history starts as committed/applied.

## Audit failure classification and repair

The initial replay failures were spec/trace consistency defects, not evidence
of an implementation defect:

1. TLC's NDJSON number path truncated native zxids at 32 bits, collapsing epoch
   boundaries. `normalize-trace.jq` now adds `state.modelZxid = epoch*100+counter`
   while retaining raw `state.zxid`; `Trace.tla` consumes the projection and
   checks raw/event-specific fields. Original bytes and hashes are preserved
   under `traces/original/`.
2. One retained marker layout wrote `ProposalReceived` after `logRequest`; the
   independent sync processor could emit `LogAppend` first. A narrowly guarded
   silent receive models that already-completed source call, and the later
   marker must still be consumed and validated.
3. A leader can observe a late epoch-support connection after its epoch is
   established. Trace replay now checks that source branch with an `Observe`
   transition rather than falsely reopening discovery.
4. Sync application, restored committed state, broadcast-ready guards, and
   NEWLEADER acknowledgement eligibility were refined from the exact-old call
   order. The baseline properties remain present and are checked unchanged;
   `PipelineOrdering` gained only the explicit exact-source SNAP deserialize
   recovery window.

## Results

The fresh harness test passed and emitted 286 NDJSON events spanning 28 event
names. The final trace suite validated every five retained normalized traces,
each with exit code 0 and zero queued states. Canonical base BFS completed with
5,413,931 generated / 779,347 distinct states and a zero queue. Canonical MC BFS
completed with 1,455 generated / 404 distinct states and a zero queue. Broader
two-voter fault/client runs reached substantial open frontiers under their
outer timeout; their logs are preserved only as limited evidence.

No implementation bug is claimed by this repair. `spec/findings.json` is empty;
all changes are validation/specification/harness fidelity repairs against the
same exact-old source.

