# Concerns about the model and contradicting evidence

These are observations from reading the model (`spec-original/`) against the source
at the base revision. Line numbers below refer to `spec-original/` (the annotated copy
only adds comment lines). They were found by reading the model, **not** by running TLC.
Nothing here was changed in the model.

## A. Properties that hold by construction (the check cannot fail)

### A1. `ElectionSafety` is enforced by a guard on its own history variable
- `WinElection` (base.tla:110-126) requires `leadersByEpoch[ep] = {}` (base.tla:116) and then
  sets `leadersByEpoch[ep] = {candidate}`. In `base.tla`, `leadersByEpoch` is written only by `Init` and by this action (`Trace.tla` writes it from observations).
  So `ElectionSafety` (base.tla:544) is true in every reachable state no matter what the
  election does. The guard reads global knowledge that no real server has.
- In the code, a single leader per epoch comes from followers acking a given epoch at most once
  (`Learner.java:513-517`, the `-1` reply) and from the leader choosing an epoch newer than
  every accepted epoch it sees (`Leader.java:1401-1402`, `getEpochToPropose`). The model has
  neither mechanism: `CastVote` (base.tla:97-107) lets one voter be added to the vote sets of
  several candidates at once, so two candidates can both reach `Quorum`. Only the guard on line
  116 then stops two leaders in one epoch.
- So the invariant cannot detect a regression in the real mechanism. To make it meaningful,
  epoch uniqueness should come from per-server state (acceptedEpoch/ACKEPOCH bookkeeping), not
  from a guard on `leadersByEpoch`.

### A2. `ApplyRequiresCommitCertificate`: second conjunct is a guard; certificates can be self-issued
- `ApplyOne` (base.tla:423-433) requires `commitCertified[ent.id]`, so the second conjunct of
  `ApplyRequiresCommitCertificate` (base.tla:558) holds by construction.
- `ObserveCommit(s, t, ep)` (base.tla:332-343) lets any following server in `sync`/`broadcast`
  commit its next proposed entry and set `commitCertified[t] = TRUE`. It needs no COMMIT
  message, no ack quorum and no leader involvement. Together with `QueueLearnerProposal`
  (base.tla:316-329), where a follower adds a fresh, unused txn to its own `proposed`/`queued`,
  a follower can invent, "certify", commit and apply a transaction the leader never proposed.
  The certificate therefore does not stand for the quorum acknowledgement that the evidence
  requires (`Leader.java:902`, `zookeeperInternals.md:117`).
- `commitCertified` and `acked` are indexed by txn id only, not by (id, epoch) or by leader
  (base.tla:65-66, `DeliverAck` base.tla:377-386). Acks delivered to any server, including a
  former leader, count toward a later `Commit` of the same id. An ack also survives a later
  TRUNC/SNAP that removes the entry from the acker's log. In the code, acks are tracked per
  proposal of the current leader (`Leader.processAck`, `outstandingProposals`).

### A3. `CommittedHistoriesPrefix` cannot be violated under the configured bounds
- Every cfg except `Trace.cfg` uses `Txn = {t1}`. `usedTxn` (Propose base.tla:283,
  QueueLearnerProposal base.tla:320) lets each id enter the system once with one epoch, so at
  most one distinct `Entry` exists in any run. Any two sequences over one value are
  prefix-comparable, so `CommittedHistoriesPrefix` (base.tla:551-553) is vacuously true in
  `MC.cfg`, `MC-small.cfg` and `base.cfg`.
- If `Txn` is enlarged, concern A2 predicts *spurious* violations: two followers can each
  invent and commit a different txn through `QueueLearnerProposal` + `ObserveCommit`.

### A4. `SyncCompletionJustified`: `syncJustified` is not tied to the current leader or epoch
- `EnterBroadcast` (base.tla:245-254) requires `syncJustified[s]` and
  `currentEpoch[s] = acceptedEpoch[s]`, so the invariant mostly restates that guard.
- `FollowLeader(s, l)` (base.tla:129-139) has no guard on `role[s]`/`phase[s]` and does not
  reset `syncJustified`, `syncSource` or `syncMode`. By inspection, a follower already
  synchronized with leader A can do: `FollowLeader(s, B)` → `AcceptEpoch(s)` →
  `EnterSyncPhase(s, B)` → `PersistCurrentEpoch(s)`, which accepts the stale
  `syncJustified[s] = TRUE` → `EnterBroadcast(s)`. It then reaches `broadcast` under B without
  any `SelectSync`/`CompleteSync` with B. `SyncCompletionJustified` still holds. After that,
  `ReceiveProposal` appends B's new-epoch proposals to a history that was never reconciled with
  B's. (This needs a re-election with 3 servers and one crash. I did not confirm reachability
  within depth 23.) In the code every new leader connection goes through `registerWithLeader`
  and `syncWithLeader` (`Follower.java:91-110`).

### A5. `NoIllegalRollback` is partly self-certifying, and DIFF is not held to monotonicity
- `rollbackAuthorized` is set by the same actions that roll back (`CompleteSync`
  base.tla:226, `Crash` base.tla:462). The property therefore only checks that *other*
  actions never shrink histories.
- `CompleteSync` authorizes rollback for every sync mode, DIFF included. The source says a DIFF
  sync builds on top of existing state ("In the DIFF case we don't need to do a snapshot because
  the transactions will sync on top of any existing snapshot", `Learner.java:553`). A DIFF sync
  that shrinks `committed`/`applied` would go unreported.
- `SelectSync` checks `DiffAllowed`/`TruncAllowed` when the mode is chosen. `CompleteSync`
  (base.tla:206-229) copies `durable[l]` later without re-checking. In between, the follower can
  grow its own log (`QueueLearnerProposal` in phase `sync`, then `AppendOne`/`FsyncOne`) and the
  leader can move to `broadcast` and append. The installed history can then differ from what the
  chosen mode allowed, and the overwrite is authorized anyway. All three modes produce the same
  post-state apart from `snapshot`.

## B. Places where the model is weaker or stronger than the code's own checks

### B1. `EpochHistoryConsistency` second conjunct is weaker than the code's startup check
- The model checks `LastEpoch(durable[s]) <= acceptedEpoch[s]` (base.tla:569). The code refuses
  to start when the epoch of the last processed zxid exceeds **currentEpoch**
  (`QuorumPeer.java:1122-1126`, "The current epoch, ..., is older than the last zxid").
- In the model, `CompleteSync` installs `durable[l]` before `PersistCurrentEpoch`. If the leader
  is already in `broadcast` (CompleteSync does not constrain `phase[l]`), its log can hold
  new-epoch entries. A `Crash` in that window leaves a durable entry newer than `currentEpoch`,
  a state the code would reject on restart. The model's invariant does not flag it.
- In the code, the SNAP path takes the snapshot on NEWLEADER before `setCurrentEpoch`
  (`Learner.java:739-743`). It is worth checking whether the same window exists there. I did not
  verify this.

### B2. `OneActiveLeaderPerEpoch` uses the model's atomic epoch assignment
- `WinElection` sets the winner's `acceptedEpoch` to `ep` at election time (base.tla:120). In
  the code a LEADING peer keeps its old `acceptedEpoch` until `getEpochToPropose` gathers a
  quorum (`Leader.java:1408-1410`). This ordering is deliberate (commit f8f15de5,
  "ZOOKEEPER-1291. AcceptedEpoch not updated at leader before it proposes the epoch").
- So in the code, a new LEADING peer and a stale leader of the previous epoch can share the same
  `acceptedEpoch` for a while. Read literally on QuorumPeer state (`LEADING` ∧ acceptedEpoch),
  the invariant does not hold in the code. Any mapping from code to model must take "leading" to
  mean "has completed getEpochToPropose".
- The model's new epoch is `acceptedEpoch[candidate] + 1`. The code uses the maximum over the
  connecting quorum plus one (`Leader.java:1401-1402`).

### B3. Restart replays the whole log into the DataTree; the model keeps this out of every property
- `FileTxnSnapLog.restore`/`fastForwardFromEdits` (`FileTxnSnapLog.java:243`, `317-355`)
  replays every logged txn into the DataTree, committed or not. The model puts this replay in
  `recovered` (`Restart`, base.tla:468-477), which no property constrains. After a restart,
  `applied` stays at the snapshot (`Crash` base.tla:456-457).
- So `ApplyRequiresCommitCertificate` and `NoIllegalRollback` say nothing about the code's
  post-restart in-memory state. That state can contain uncommitted txns until the next
  sync/TRUNC.

### B4. `HistoryAtLeast` compares log lengths
- The vote predicate (base.tla:92-95) compares `currentEpoch`, then `Len(durable)`. The code's
  `totalOrderPredicate` (`FastLeaderElection.java:722-745`) compares epoch, then zxid, then
  server id, and the zxid comes from `getLastLoggedZxid` (DataTree `lastProcessedZxid`). Logs of
  equal length but different content compare as equal in the model. This is not a property, but
  it feeds election and sync.

## C. Evidence that contradicts or limits a property as written

- `OneActiveLeaderPerEpoch`: `zookeeperInternals.md:278` says "two servers simultaneously think
  they are the leader" can happen (TCP timeout smaller than `syncLimit * tickTime`). This
  contradicts the global reading of `zookeeperInternals.md:246` ("only one active leader at a
  time"). It does not contradict the per-epoch formula as long as the two leaders hold
  different epochs. B2 shows the code can briefly have both in the same acceptedEpoch.
- `PipelinePrefix` (snapshot conjunct): `zookeeperAdmin.md:2589-2600` says snapshots are
  *fuzzy*: "The snapshot, then, may not correspond to any data tree that actually existed".
  The model treats `snapshot` as an exact prefix of `applied`. Only the zxid label (the last
  committed txn at snapshot start) has a documented guarantee.
- `NoIllegalRollback` (applied conjunct): the documented guarantees (`zookeeperOver.md:166-171`,
  `zookeeperProgrammers.md:1176-1178`) are service-level and per client session. They do not
  say a single server's in-memory state never shrinks outside crash/sync. The per-server form
  in the model is stronger than the documents.

## D. Harness / configuration observations

- `Trace.tla` reads `../traces/follower-snap.ndjson` by default (Trace.tla:7-9). No trace
  files exist anywhere in `/work`, and the source has no probe that emits the event names
  (`SyncSelected`, `TxnDurable`, `BroadcastReady`, ...). So `Trace.cfg`/`TraceMatched` cannot
  be reproduced from this workspace.
- `TraceObservedStep` builds two invariants into its preconditions: `Cardinality(Leading(nr)) <= 1`
  (Trace.tla:256, stronger than `OneActiveLeaderPerEpoch`) and `nc[s] <= na[s]` (Trace.tla:257,
  the first conjunct of `EpochHistoryConsistency`). A trace that violates them shows up as a
  `TraceMatched` failure (trace not accepted), not as an invariant violation. This hides which
  property failed.
- `TraceRole` (Trace.tla:44-50) maps a logged `looking` role to `following` for the two
  follower-* scenarios (a documented fixture projection). A real role mismatch in those
  scenarios would be masked.
- `MC.cfg` and `base.cfg` add `CONSTRAINT CanonicalDepthBound` (`TLCGet("level") <= 23`,
  base.tla:597). Every invariant and `HistoryPositionsMonotonicExceptRecovery` is verified only
  up to depth 23, not over all reachable states.
- In the model, `proposed` and `queued` are always updated together (Propose, ReceiveProposal,
  QueueLearnerProposal, CompleteSync, Crash), so `IsPrefix(queued[s], proposed[s])` in
  `PipelinePrefix` is trivially true.
