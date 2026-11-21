# Validation repair changelog

## Round 1 - Trace Validation

- [fix] Trace selection: removed the hard-coded `follower-snap` scenario
  predicate so every trace record in the caller-selected NDJSON file is an
  obligation (audit failures: follower DIFF, quorum, and restart/recovery).
- [fix] Trace domain: generalized servers, epochs, and zxid counter values to
  cover all five retained exact-old traces without modifying trace data.
- [fix] State validation: added schema checks, post-state checks for all five
  captured peer fields, and event-specific zxid/pipeline checks for all 15
  instrumented event names.
- [fix] State-transition validation: replaced trace-fed common-field assignments
  with source-backed event gates. Accepted/current epoch, role, phase, and sync
  mode can now change only at their corresponding probes (including the nested
  election phase update in `setPeerState`), so post-state comparisons are not
  tautologies. Protocol leaders are recorded when accepted-epoch persistence
  binds the newly elected role to its Zab epoch.
- [fix] Trace abstraction: represented uninstrumented leader-side proposal and
  commit callbacks by the minimum implied common prefix, and treated snapshot
  installation as the explicit history-replacement boundary.

## Round 1 - Model Checking

- [fix-spec] `EnterSyncPhase`: required the follower's accepted epoch to equal
  the leader's persisted epoch, matching `Learner.registerWithLeader` before
  synchronization. This closes the Case-B counterexample in
  `base-canonical-repair.log` where an epoch-1 entry became durable at a
  follower whose accepted epoch was still 0.
- [fix-spec] `ReceiveProposal`/`ReceiveCommit`: required a broadcast learner's
  synchronized current epoch to match the packet epoch. This closes the
  round-3 stale-connection counterexample where a follower still synchronized
  to epoch 1 accepted an epoch-2 proposal from a re-elected server with the same
  identity.
- [fix-spec] `CompleteSync`: bound completion to equal accepted epochs at the
  learner and sync source. This closes the depth-24 counterexample where a
  pre-crash TRUNC session completed after the same leader identity restarted
  in a later epoch.
- [fix-spec] Canonical bounds retain three voters, two epochs, one transaction,
  and one bounded crash/drop/snapshot while permitting both canonical base and
  MC BFS to exhaust naturally. The broader prior run remains preserved as
  limited open-frontier evidence.
- [fix] Canonical exploration: enabled `Permutations(Server)` symmetry in base
  and MC configs. This quotients only voter renamings and leaves all three
  servers, behaviors, actions, and properties in scope.
- [fix] Canonical exploration: added an explicit TLC level-23 state constraint
  to base and MC. The bound exceeds the preserved depth-22 mutation/apply
  witness and retains crash/restart/re-election prefixes; only a natural
  zero-queue completion counts as canonical success.

## Result

Converged in one repair round. All five retained exact-old traces passed before
canonical checking. Canonical base BFS completed with 52,034,534 generated and
6,354,157 distinct states; canonical MC BFS completed with 171,870,841 generated
and 21,701,056 distinct states. Both reached depth 23, exited zero, reported no
violation, and left zero states on the queue. No bug-hunting finding was produced.
The older timeout/open-frontier logs remain preserved as limited evidence only.
