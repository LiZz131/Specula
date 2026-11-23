> Translated from the Chinese analysis of 2026-11-21; the rubric is [rubric.md](rubric.md).

> **2026-11-23 correction from TLC evidence** ([evidence/case-010/](evidence/case-010/README.md))
> - The "exhaustive oracle over 144,904 states" used the scenario-view cfg `Evidence-oldSPV.cfg`; the run on the main cfg did not finish. The original `SnapshotPublishedValid` has no violation on v1's two regular cfgs that finish.
> - v0's miss is confirmed as unrepresentable: `base.tla:318-330` flushes the whole queue to `durable` on exit while serving; the premise is reachable at step 26 of v0's own MC-1 cfg. v1 and v2 reach the bug in 23 and 25 steps.

# case-010: ZooKeeper Zab · follower sync and shutdown — invariant evolution quality and missed-report attribution

> Per the [rubric](rubric.md) (epoch-1). Each arm has only r1, a single sample. No Gold or scoring material was read.
> Path abbreviations (all relative to `research/ci-evolution/inv-e2e/`): `O=../blind-incremental-bugs/blind-incremental-v0/case-010/.specula-output` (the old model), `E<arm>=results/<arm>/case-010/r1`, `A<arm>=WORK/attempts/<arm>/case-010/r1/log/activity.jsonl`, `S=WORK/subjects/case-010`. `WORK` is the experiment's work directory, archived outside git (see `../../README.md`, section Storage). The timeline of a run is `E<arm>/timeline.md`.
> Note on time: the "minutes" in this document are **real wall-clock time** computed from the `timestamp` of activity.jsonl (relative to the first event). The "~min" in section 2 of the earlier per-case notes (not in this repository) was converted linearly from turn numbers, with an error of up to about 55 minutes (see 6.2). `[N]` is a turn of timeline.md, and `A:L<n>` is a line number of activity.jsonl.

## 1. Conclusion

**Root cause of the missed report (one sentence):** In reconnaissance, at minute 2, v0 read the base class `ZooKeeperServer.shutdown(){ shutdown(false); }` and equated the old call `zk.shutdown()` with `shutdown(false)`. It did not look for a subclass override according to the declared type of `Learner.zk`, which is `LearnerZooKeeperServer`. It also carried the sentence "graceful shutdown drains the sync thread" from the old brief unchanged into the new `LearnerShutdown`. As a result, in the new model a serving learner still drains when it exits, and the SyncRequestProcessor leak introduced by the update does not exist in the model. This miss has nothing to do with properties, budget or truncation. Classification: unread-code + equivalence-claim + anchoring (from old prose, not from old TLA).

**Evolution quality of the three arms:**
- **v2 is the best.** It changed only the impl-abstraction exemption clause of `MonotoneUnlessRecovery`, with a trace separating state (E3) and a negative control (E3c), and the requirement source and ledger status are both correct. The requirement property `OrderedHistories` was kept unchanged and was used directly to report the leak. One small gap: the exemption was extended to three kinds of step (MODE, SNAPPED, NEWLEADER), but E3 covers only the MODE step.
- **v1 is second.** Both weakenings of existing properties (`OrderedHistoriesV1`, `MonotoneUnlessRecoveryUpd`) have TLC separating states and controls. There are two problems: `SnapshotPublishedValid` is registered as keep, but the regular cfgs actually check the weaker V1; and the requirement source of E_MON2 is the update's own comment.
- **v0 is the weakest.** It modified 4 existing properties without evidence: OrderedHistories, SyncEntryJustified (x2), ActiveLeaderUniqueness and MonotoneStep. The weakening of SyncEntryJustified was reactive, and both v1 and v2 show that no weakening is needed (changing the model is enough). None of these modifications is the cause of the missed report.

**Key corrections to the mechanical table:** None of v0's 7 "deleted" is a real deletion, and none is an intermediate state caused by truncation. One is a rename-weakening (`ActiveLeaderUniqueness`→`LeaderUniquenessPerEpoch`), and 6 are canary renames. The cfg file names did not change, and all of them produced witnesses on the final model. Also, the cfg parser of `prop_events.py` has a bug: a PROPERTIES name that follows INVARIANTS in the same cfg is swallowed. As a result `MonotoneUnlessRecovery` and `TraceMatched` are not in the "existing properties", and the modifications that all three arms made to `MonotoneUnlessRecovery` are not counted at all.

## 2. Update summary

- Two source changes: `zk.shutdown()` in `Learner.shutdown` became `zk.shutdown(self.getSyncMode().equals(SNAP))` (`S/buggy-tree/.../quorum/Learner.java:864`); and `ZooKeeperServer.shutdown(boolean)` now does `zkDb.clear()` before returning when `!canShutdown() && fullyShutDown` (`ZooKeeperServer.java:803-810`). A new test `QuorumPeerMainTest#testDiffSyncAfterSnap` was also added.
- The implied semantic change is in dynamic dispatch. The declared type of `Learner.zk` is `LearnerZooKeeperServer` (`Learner.java:87`). This class overrides only the no-argument `shutdown()` (`LearnerZooKeeperServer.java:155-173`). The override calls `super.shutdown()` first, then `syncProcessor.shutdown()` (:168). The base-class `shutdown(boolean)` closes only the `firstProcessor` chain (around `ZooKeeperServer.java:835`). The follower's `syncProcessor` is not on this chain (`FollowerZooKeeperServer.java:74-77`). So in the new code, when a serving learner exits, the SyncRequestProcessor is neither stopped nor drained.
- Affected model elements: the learner exit action (absent from the old model), the separation of the in-memory database from disk (absent from the old model), the sync split (the old model's `CompleteLearnerSync` is atomic), and the sync queue and flush (`QueueForSync`/`FlushTxnLog`). The properties that read this state are `OrderedHistories`, `MonotoneUnlessRecovery`, `SyncEntryJustified`, `NormalAckHasDurabilityEvidence` and `SnapshotPublishedValid`.

## 3. Event table

Counts of keep entries that are not listed one by one:
- v0: AcceptedEpochGECurrentEpoch, CommittedPrefixAgreement, NormalAckHasDurabilityEvidence, ApplyHasCommitCertificate and SnapshotPublishedValid. The text of these 5 properties did not change, but the actions that produce `applied`, `committed` and `durabilityEvidence` were all rewritten. There is no record of a per-property review for any of the 5. They are classified as keep-affected with Q5 = missing, merged into one row of the table. 6 canaries are renames (see section 6), and 8 are new (`CanaryNo*` x4, `Never*` x4).
- v1: ActiveLeaderUniqueness and AcceptedEpochGECurrentEpoch are keep. 8 new canaries (`*Unreachable`).
- v2: ActiveLeaderUniqueness, AcceptedEpochGECurrentEpoch, NormalAckHasDurabilityEvidence, SnapshotPublishedValid, 6 `*Unreachable` and `TraceMatched` are keep. 5 new canaries (`Upd*Unreachable`).

| arm | property | event | Q1 | Q2 | Q3 | Q4 | Q5 | Q6 | Q7 | source and notes |
|---|---|---|---|---|---|---|---|---|---|---|
| v0 | OrderedHistories | weaken + representation | needed | too-weak (partly restored by new properties) | ok | untested | weak | proactive | none (inference) | `Ev0/output/spec/base.tla:1166-1176`. Originally `prepared`, `durable` and `recoveryVisible` all had to be gap-free prefixes of `TxnOrder` (`O/spec/base.tla:563-572`). Now they need only be strictly increasing (`Ordered`). `recoveryVisible` was replaced by `memDb`, and `syncBuf` was added. This is the version at the first write of base.tla at minute 27.2 ([94], `Av0:L1281`), and there was no violation at that time. The rationale is one sentence about representation (`changelog.md:16`, "V0 dense prefixes could not represent divergent records or TRUNC"). The requirement "a committed transaction cannot have a gap" was restored only for durable (new `DurableHistoryConsistent`, `base.tla:1203-1211`). The gap-free requirement on `prepared` and `memDb` was lost. v0's model has no leak, so this weakening did not hide the leak. Inference: if the model had the leak, `Ordered(durable)` could reject out-of-order replay, and `DurableHistoryConsistent` could reject a committed gap. |
| v0 | SyncEntryJustified (1st) | weaken | not-needed | unclear | ok | untested | impl-as-req | reactive | none | Minute 33.3 ([115], `Av0:L1477`). After smoke-sim-2 violated it, `syncStage # "EXITED"` was added. The violation was triggered by v0's own modeling choice: `LearnerShutdown` sets `syncComplete` to FALSE (`base.tla:346`) while the phase is still BROADCAST. The rationale is "neither window serves clients", citing line numbers of QuorumPeer.java (`changelog.md:23`), which is implementation behavior. v1 (`Ev1/output/spec/changelog.md:20`) and v2 (`Ev2/output/spec/changelog.md:20`) met the same phenomenon and both postponed the reset of `syncComplete`, keeping the property unchanged. |
| v0 | SyncEntryJustified (2nd) | weaken | not-needed | unclear | ok | untested | impl-as-req | reactive | none | Minute 47.7 ([194], `Av0:L1963`). After smoke-sim-6 violated it, `role \in {LEADING, FOLLOWING}` was added, and the original `ELSE FALSE` branch (a non-leader/follower must not be in BROADCAST) is gone (`base.tla:1186-1194`). For the same window, v2 merged setPeerState into one step (`Ev2/.../changelog.md:24`). |
| v0 | ActiveLeaderUniqueness → LeaderUniquenessPerEpoch | weaken (rename) | needed (v0 added a `LeaderShutdown` that loses quorum; in the old model a leader is never deposed) | correct | ok | ok (the smoke-sim-3 counterexample is exactly a state where the old property is false and the new one is true, but it was not archived as evidence) | weak | reactive | none | Minute 37.5 ([125], `Av0:L1577`). The new definition is at `base.tla:1151-1160`. The requirement source is `model-scope.md:43`, "at most one active leader per epoch" (I checked it in `ws/model-scope.md` of the `Av0` workspace), and the changelog cites it (`changelog.md:24`). |
| v0 | (companion) LeaderPropose requires `Quorum(Ensemble(l))` | model-narrowing | needed | unclear | ok | untested | weak | reactive | unclear | Same round ([125]). A deposed leader cannot propose during the detection window, so that "id order = zxid order" (comment of LeaderPropose in `base.tla`; brief §8.5 records it as an exclusion, `modeling-brief.md:226-228`; the guard is at `base.tla:913`). |
| v0 | MonotoneUnlessRecovery / MonotoneStep | replace (the exemption was replaced by a syncStage transition; committed/applied were strengthened from comparing length to `PrefixOf`; a globalCommitted prefix was added; durable still compares only length) | needed (after the sync split, the old syncComplete exemption no longer matches the real rollback steps) | correct (`model-scope.md:47-48`) | ok | untested | weak | proactive | none | `base.tla:1218-1229`, minute 27.2 ([94]). **The changelog has no entry for this, but it is not entirely unrecorded:** `modeling-brief.md:223` says "SyncEntryJustified, MonotoneUnlessRecovery: revised for exit windows / explicit SNAP-TRUNC replacement", and `base.tla:1218-1220` has a comment. There is no separating state. |
| v0 | 5 keep-affected properties (see above) | keep-affected | needed (review) | correct | ok | ok (regular cfgs check them as usual, 28 cfgs) | missing | — | none | Brief §8.4 lists only the modified properties (`modeling-brief.md:212-224`). For these 5 it does not say, one by one, why they still hold. |
| v0 | TypeOK / MCTypeOK | representation | needed | correct | ok | ok | weak | proactive | none | New variables were added, plus the constraint `~memInit => memDb = <<>>` (`base.tla:1109-1149`). |
| v0 | self-added ReportedHistoryDurable | weaken (the antecedent of the new property was narrowed) | unclear | unclear | ok | ok | impl-as-req | reactive | none | After smoke-sim-4 violated it, followers that had already synced were excluded (`changelog.md:25`). MC-1 was later reported with this very property. The scenario is a learner that has exited and is in LOOKING, which is not in the excluded range. |
| v1 | OrderedHistories → OrderedHistoriesV1 | weaken | needed (v1 explicitly models lost proposals and duplicate writes) | correct (gap part) / unclear (adjacent duplicates) | ok | ok | valid / weak | proactive | none | `Ev1/output/spec/base.tla:1019-1029`. Evidence: E_OH (mc separating state, citing the comment at `LearnerHandler.java:991-992`), E_OHc (constructed negative control), E_OH_dup (requirement unknown, recorded in `unresolved`). The original is still checked in `MC.cfg` (MCCoreNext) and `base.cfg`. The leak introduced by the update is caught by the new `RecoverableHistoryComplete` and `DurableReplayOrdered`, so it was not hidden. |
| v1 | MonotoneUnlessRecovery → V1 → Upd | weaken (also changed to quantify per server: other servers in the same step must also be monotone, which is a slight strengthening and is not registered) | needed | correct (split steps) / unclear (clear-database step) | ok | ok | valid (E_MON) / weak (E_MON2) | V1 is proactive; adding the clear step is reactive | none | `base.tla:1068-1080`, `UpdateProps.tla:66-79`. The requirement source of E_MON2 is `new-source/.../Learner.java:862-863` and `ZooKeeperServer.java:801`, that is, the update's own comment and javadoc. Using them to justify the change risks circular reasoning. The original is checked only in `Evidence-oldMON.cfg`. |
| v1 | SnapshotPublishedValid | registered as keep; in fact weaken + unchecked | not-needed (v1's own oracle shows there is no separating state after the fix) | too-weak (V1 requires only snapshot ⊑ globalCommitted, which is weaker than the original snapshot ⊑ applied[s]) | ok | ok | weak (registration and cfg disagree) | reactive | none | The evidence registration says `decision: keep`, "V1 additionally enabled". But `InvariantSet` (`base.tla:1082-1086`) and the 16 regular cfgs use `SnapshotPublishedValidV1`. The original is checked only in `Evidence-oldSPV.cfg` and `Evidence-oldSPV-full.cfg` (I verified this with grep). The oracle `output/final-evidence-oldspv.log` searched 144,904 distinct states completely and found no violation, so detection is not affected. |
| v1 | SyncEntryJustified | keep-affected | needed | correct | ok | ok | valid (K_TRACE) | — | none | Violated 3 times (timeline lines 163, 167, 300), and each time solved by changing the model (`changelog.md:20`: the reset of `syncComplete` was moved to LearnerExit/ChooseSyncMode). |
| v1 | CommittedPrefixAgreement, NormalAck…, ApplyHas… | keep-affected | needed | correct | ok | ok | valid (K_TRACE/K_MC) | — | none | There are corresponding entries in `invariant-evidence.json`. |
| v1 | OrderedHistoriesMem (used in the residual search) | (search device) | — | — | — | — | missing | — | none | `UpdateProps.tla:85`, used to skip the known defect class. It is not registered, but it is not a decision about a property. |
| v2 | MonotoneUnlessRecovery | weaken (only the impl-abstraction clause was changed) | needed | correct | ok | ok | valid (MODE step) / weak (SNAPPED, NEWLEADER steps) | proactive | none | `Ev2/output/spec/base.tla:1168-1178`; the REQ-EVIDENCE block starts at :1180. E3 is the `ReceiveSyncMode(TRUNC)` step on a real trace: TLC judges the old version false and the new one true; E3c is the control. The exemption was extended to 3 kinds of step, and E3 proves only that the MODE step is necessary. The two requirement clauses (the non-exempt branch) were not touched. |
| v2 | OrderedHistories | keep-affected | needed | correct | ok | ok | valid (E4, E4k, E4r, citing `zookeeperInternals.md:229`) | — | **enabled** | The counterexample of MC-2 (the leak) violates exactly this property (`Ev2/output/spec/bug-report.md`, section MC-2). E4r is the 95th state of the reproduction trace on the new code. |
| v2 | SyncEntryJustified | keep-affected | needed | correct | ok | ok | weak (no separate evidence entry; relies on the changelog) | — | none | Violated 2 times (timeline lines 243, 310), each time solved by changing the model (`changelog.md:20,24`). |
| v2 | TypeOK / MCTypeOK | representation | needed | correct | ok | ok | valid (E5k) | proactive | none | Registered as `representation-only`. |
| v2 | CommittedPrefixAgreement, ApplyHasCommitCertificate | keep-affected | needed | correct | ok | ok | valid (E5k) | — | none | |

New properties: v0 has 4 (DurableHistoryConsistent, LeaderCompleteness, ReportedHistoryDurable, SnapExitReportsDisk); v1 has 5 (ExitedLearnerMemoryBackedByLog, RecoverableHistoryComplete, RecoverableCommittedPrefix, DurableReplayOrdered, ClearedOnlyAfterSnapExit); v2 has 2 (UpdIdleDbBackedByDisk, UpdDurableCoversCommitted).

## 4. Per-arm summary

**v0**
- Good: the new `DurableHistoryConsistent` puts "committed must have no gap" on durable, and the consequence of MC-1 was later caught by it. The weakening of `ActiveLeaderUniqueness` has a requirement source. All `[inv]` modifications happened between minutes 27 and 48, and MC-1 first appeared at about minute 111 ([342]). So there was no case of "weakening away a counterexample".
- Problems: none of the modifications to the 4 existing properties has a separating state. For the two weakenings of SyncEntryJustified, the violation was triggered by v0's own modeling choice, and the comparison arms show that no weakening is needed. The change to MonotoneStep is not written in the changelog.
- Under-reaction:
  1. The 5 keep-affected properties were not reviewed one by one.
  2. **More important, in the model:** the assertion about `LearnerShutdown` draining, written at minute 27, was never questioned again, even when v0 itself changed this action at minute 119 (see 5.4).

**v1**
- Good: both weakenings have TLC separating states and controls. The uncertain part (adjacent duplicates) was honestly written into `unresolved`. SyncEntryJustified stayed unchanged, and violations were resolved by changing the model.
- Problems: the SnapshotPublishedValid registration disagrees with the configuration. The requirement source of E_MON2 is in fact the implementation (the update's own comment). The change of MonotoneStepV1 to per-server quantification is not registered.
- Under-reaction: no obvious case of something that should have been changed but was not.

**v2**
- Good: it changed only the impl-abstraction clause that the ledger allows to be modified, with evidence from real traces. The requirement property was kept unchanged and used directly to report the bug. The two unknown properties were also kept unchanged.
- Problems: the exemption was extended to 3 kinds of step, and only 1 has a separating state. The "keep" of SyncEntryJustified has no separate evidence entry.
- Under-reaction: none seen.

## 5. Missed-report attribution (v0 missed the SyncRequestProcessor leak introduced by the update)

### 5.1 Where the wrong abstraction came from

- **The old TLA model did not contain this abstraction.** The old model has no learner exit action. `GracefulShutdown` only sets `running` to FALSE (`O/spec/base.tla:153-162`), and the old `FlushTxnLog` still requires `running[s]` (`O/spec/base.tla:432-434`). So the old model does **not** drain the queue at shutdown. It freezes it.
- **The abstraction came from old prose.** The old brief says "Graceful shutdown drains the sync thread and flushes pending work … (`SyncRequestProcessor.java:254-270`; `ZooKeeperServer.java:803-850`)" (`O/modeling-brief.md:88`), and the old report has a corresponding sentence (`O/analysis-report.md:92`). v0 kept these two sentences **verbatim** at `modeling-brief.md:88` and `analysis-report.md:92` of its own output. The comment of the new `LearnerShutdown` cites the same line numbers: "Running server: SyncRequestProcessor.shutdown drains and flushes (SyncRequestProcessor.java:254-270)" (`Ev0/output/spec/base.tla:319-320`). The comment of the new `GracefulShutdown` was also changed to "the role objects then drain their SyncRequestProcessor" (:262).
- The old prose is in fact correct about the old code, but the reason it is correct is the `LearnerZooKeeperServer.shutdown()` override. The `ZooKeeperServer.java:803-850` that the old prose cites does not shut down the syncProcessor. v0 inherited this conclusion and this inaccurate source, and applied them to a new call that no longer goes through the override.
- Judgment: this wrong abstraction was newly introduced into the TLA by v0, but its vocabulary and assertion were inherited from the written material of the old model. This corrects a claim of the earlier per-case notes (not in this repository): v0 did not model "following the action semantics of the old model", because the old model has no such action.

### 5.2 At which step it was fixed

- **Reconnaissance (01), minute 2.4, [45] (`Av0:L160-161`).** v0 read lines 760-880 of `ZooKeeperServer.java`, and the tool result contains `public void shutdown() { shutdown(false); }`. From then on its artifacts always write the old behavior as `shutdown(false)`:
  - `base.tla:26`: "FALSE = exact-old control (Learner called zk.shutdown() == shutdown(false))";
  - the old/new behavior table at `analysis-report.md:137`, whose header says "Old (`shutdown(false)`)" directly. Line 143 says "any mode after UPTODATE … RUNNING | drain sync processor, fastForwardDataBase | unchanged".
- **ci-context, minute 24.0 (`Av0:L1269`).** The source change is summarized as "Learner.shutdown passes fullyShutDown = (syncMode==SNAP); … shutdown(true) on non-running zk now zkDb.clear()". Only the database-clearing side is seen.
- **Generating the Update model (04), minute 27.2, [94] (`Av0:L1281`).** `LearnerShutdown` was written into base.tla with `zkRunning ⇒ drained/flushed`, and the drain semantics never changed afterwards.
- No record of the 05 completeness review was found: grepping "completeness" in all md files of `Ev0/output` hits only the property name `LeaderCompleteness`.

### 5.3 Information gap (verified with activity)

- **What was read:**
  - `Learner.java` ([42] grep, [43] Read);
  - `ZooKeeperServer.java` 760-880 ([45]);
  - the `void shutdown` of `Follower.java` ([76], `Av0:L451`), whose result contains only `super.shutdown()`;
  - the line number of `public void shutdown` in `SyncRequestProcessor.java` ([85], `Av0:L930`, grepped only for the line number as a comment anchor);
  - `logRequest`/`commit` of `FollowerZooKeeperServer.java` ([85]).
- **What was not read:** `LearnerZooKeeperServer.java`. I checked the inputs of all 245 tool calls, and none involves this file. There was also no grep for the `shutdown` override in the subclass. At minute 38.5, the grep result at [136] (`Av0:L1634-1635`) contains `Learner.java:87: LearnerZooKeeperServer zk;`, but v0 was then looking for accessors for the probe and did not follow this type.
- For comparison: v0 does understand that "a server that is not running will not stop the sync thread". Its own MC-2 is a sync processor started in the DIFF window that keeps flushing after exit (`bug-report.md:67-73`). The old-code control of v2 also hit this variant (`Ev2/.../bug-report.md:73`). What v0 lacked is only the dispatch for an exit while serving.

### 5.4 Why the mechanisms that should have caught it did not

- **Trace validation.** The final 4 v3b traces of v0 contain 15 exits while serving (`zkWasRunning=true`), and I checked each one. But:
  - on `LearnerShutdown` the probe records only `fullyShutDown`, `zkWasRunning`, `memInit` and `memLast` (`instrumentation-spec.md:40`). `durableLast` is always null, and it does not record whether the sync thread is still alive;
  - `LearnerShutdownIfLogged` in `Trace.tla` calls only `ValidateMemPost` and not `ValidateDurablePost` (`Trace.tla:51-59,91-101`);
  - after these 15 exits and before resync, that node has no Flush event, which shows that the queue was empty at exit in the tests.

  So "drain" and "leak" cannot be told apart on the trace. The probe of v2 has an extra `syncAlive` field (`Ev2/output/instrumentation-spec.md:58`), which is true on the new code and false on the old code. This is exactly the observation that v0 lacked.
- **Canary.** v0 has no canary for "exit while serving with a non-empty queue". v1 has `ServingExitUnreachable` and `LeakedFlushAfterResyncUnreachable`.
- **Counterexample.** Step 36 of the witness path of MC-1 is "s2 exits while serving → sync processor drained, fastForwardDataBase" (`bug-report.md:26`). At minute 119.2 ([358], `Av0:L3117`), v0 modified this drain branch to deal with a spurious counterexample: it removed the ACK recorded by the drain, with the reason "closeSocket() precedes zk.shutdown (Learner.java:859-865)". It reread these lines of `Learner.shutdown`, but fixed only the ACK, and did not ask whether the drain itself happens. This is the second missed chance.
- **Completeness review:** no record (see 5.2).

### 5.5 What the comparison arms did at the same step

- **v1:** at reconnaissance minutes 1.7 to 1.8, [46]/[47] (`Av1:L144`, `L149`), it grepped `void shutdown|shutdown(` in `LearnerZooKeeperServer`, `FollowerZooKeeperServer`, `QuorumZooKeeperServer` and `LeaderZooKeeperServer`, and read lines 140-180 of `LearnerZooKeeperServer.java`. At minute 22.9 ([84], `Av1:L1244`) it wrote an old/new behavior table **with the same structure as v0's**, but branch C says "`LearnerZooKeeperServer.shutdown()` → … **then `syncProcessor.shutdown()`** | `zk.shutdown(false)` dispatches directly to `ZooKeeperServer.shutdown(boolean)`, which `LearnerZooKeeperServer` does not override" (`Ev1/output/analysis-report.md:151`). The base.tla at minute 28.4 already has `leakedQueued` (`Av1:L1366`).
- **v2:** it finished reading the overlay at minute 4.4 (`Av2:L274`, `L276`). At minute 9.7 ([63], `Av2:L552`) it said "Important lead: `Learner.shutdown` now calls `zk.shutdown(boolean)` instead of `zk.shutdown()`. Checking whether learner server subclasses override only the no-arg form.", and then grepped the shutdown of each `*ZooKeeperServer` ([64]) and the type of `Learner.zk` ([67]). At minute 20.1 `leakedQueued` already appears in ci-context (`Av2:L1056`), and it was written into base at minute 26.4 (`Av2:L1268`).
- **Did the overlay cause this: the evidence does not support it.**
  - The overlay (`divergence-evidence.md`, `ledger-usage.md`) is all about what evidence a property decision needs. The Code Observation in §6 says "runs in Validation, not Generation", and it serves separating states. It has no requirement on callee resolution or subclass overrides. Both arms found the dispatch problem while reading the source in reconnaissance, before any code observation.
  - The old worktree of v1 was built only at minute 46.0 (`Av1:L2115`), when the leak was long in the model.
  - `01-update-reconnaissance.md:8`, shared by all three arms, requires "read every changed function in both revisions with its callers, callees". v1 and v2 did callee resolution on the old version, and v0 did not.
  - So the inference in the earlier per-case notes, "the old/new worktrees let v1 and v2 see the difference earlier", does not hold. The difference comes from the exploration path. With a single sample, an indirect effect of the overlay (for example, making the agent more used to old/new comparison) cannot be excluded. Recorded as unclear.
- All three arms wrote the first version of base between minutes 24.6 and 28.4 (v0 `L1272`, v1 `L1366`, v2 `L1268`). There is no difference in time on this point.

### 5.6 Where v0's time went, and whether truncation was the cause

- Wall-clock segments (`Av0` timestamps):
  - minutes 0-24: reconnaissance and reading source, of which minutes 6-17 were spent reading skills during the Maven warm-up;
  - minutes 24-56: writing the model, smoke, harness, trace validation gate;
  - minutes 56-125: MC rounds and model fixes ("Final model is now fixed", `Av0:L3234`);
  - minutes 125-233: final campaigns F1-F6, documents, canary reruns. The last modification of base.tla was at minute 192.0 ([432]), and the last tool call was `run_F6.sh` at minute 232.8.
- Counting by the start and end times of tool calls, **about 135 minutes were spent waiting for background TLC** (commands containing `sleep`/`until`), more than half of the 233 minutes. Unguided BFS reaches only depth 28-35, while the counterexample needs 55-89 steps (`validation_limits` in `final-result.json`), so most of the time went to guided deep searches.
- Truncation was not the cause: the drain semantics were fixed at minute 27 and were not questioned in the following 200 minutes. `final-result.json` was already drafted around minute 155 (`Av0:L3447`). Only the F6 canary rerun was truncated, and the F6 logs produced witnesses between 23:36 and 23:40 (`output/final6-*`). **Budget is not in the classification.**

### 5.7 Classification

- **unread-code (primary cause):** the override of the overloaded method in `LearnerZooKeeperServer` was not looked up. This is a dynamic dispatch problem.
- **equivalence-claim:** the unverified assertion that the old `zk.shutdown()` is equivalent to `shutdown(false)` (`base.tla:26`, `analysis-report.md:137`).
- **anchoring:** "graceful shutdown drains the sync thread" from the old brief and report was carried unchanged into the new action, even with the same source (5.1).
- Not property-gap: v0's `DurableHistoryConsistent` and `Ordered(durable)` are enough to catch the consequence of the leak, provided the model has the leak. Not scope-exclusion and not budget.

### 5.8 Minimal interception points

1. **The old/new behavior table in reconnaissance (01) or update analysis (03).** Object checked: every changed call expression. Artifact: the old/new table of `analysis-report.md` needs one more column, "the method each version actually dispatches to", stating the declared type of the receiver (`Learner.zk : LearnerZooKeeperServer`), and looking up, in this type and its subclasses, the override of each of the old and new signatures, with the `path:line` of the grep result. v0 already made this table (`analysis-report.md:137-143`). With this extra column, the first row could not have been written as "Old (`shutdown(false)`)". The cost is one grep, and v1 did it at reconnaissance minute 1.7.
2. **Backstop: trace validation (Validation 2).** Object checked: every postcondition that the model claims for a changed action (here `durable' = flushed` and the sync thread being stopped). Artifact: the Trace wrapper must validate the corresponding field (`ValidateDurablePost`, or something like `syncAlive`), and at least one scenario must have a non-empty queue at exit. The `syncAlive` of v2 does exactly this.

## 6. Corrections to the mechanical table (`analysis/out/prop_events-case-010.md`)

### 6.1 Row by row

| row | mechanical table | actual | basis |
|---|---|---|---|
| v0 ActiveLeaderUniqueness | deleted; cfg 10→0 | **renamed and weakened** to `LeaderUniquenessPerEpoch` (at most one BROADCAST leader within the same epoch), still checked in all regular cfgs of MC/base/Trace/Update | `Ev0/output/spec/base.tla:1151-1160`; `MC.cfg`, `base.cfg`, `Trace.cfg` and `Update-full.cfg` all check it; `changelog.md:24` |
| v0 ApplyUnreachable | deleted | renamed to `NeverApply` | `MC.tla:236`, `MC-apply-hunt.cfg` |
| v0 CommitUnreachable | deleted | renamed to `NeverCommit`. The old one is a state predicate (∃t: Quorum(commitWitness[t])), the new one is an action marker ("Commit" ∈ seen); the semantics are close | old `O/spec/MC.tla:245,252`; new `MC.tla:235` |
| v0 ElectionUnreachable | deleted | renamed to `NeverElection` | `MC.tla:234` |
| v0 RecoveryUnreachable | deleted | renamed to `NeverRestart` | `MC.tla:238` |
| v0 SnapshotUnreachable | deleted | renamed to `NeverSnapshot` | `MC.tla:237` |
| v0 SyncUnreachable | deleted | renamed to `NeverCompleteSync` (the marker moved from the atomic `CompleteLearnerSync` to the last step after the split) | `MC.tla:242`; first-line comment of `MC-sync-hunt.cfg`, "Inherited V0 reachability hunt rebased to MC v3 sentinel NeverCompleteSync" |

- All 6 canaries stay under their original `MC-*-hunt.cfg` file names, and on the final model `output/final6-mc-*-hunt-*.log` all report the expected violation (the witness exists). So they are **not intermediate states from truncation, and were not moved to another file**. They were only renamed, and the mechanical table matches by name, so it judged them deleted.
- The last modification of base.tla by v0 was at minute 192.0; F6 was rerun on the final model.
- The real number of deletions in v0 is 0. The real number of weakenings (weaken/replace) is 4: OrderedHistories, SyncEntryJustified, ActiveLeaderUniqueness, MonotoneStep. The last one is invisible to the mechanical table, for the reason in the parser problem after 6.1.

Other rows:

| row | mechanical table | actual |
|---|---|---|
| `helpers: PrefixOf` of v0, v1 CommittedPrefixAgreement / SnapshotPublishedValid etc. | listed as a helper change | False alarm. `PrefixOf` was rewritten from `∃n∈0..Len(b): a = SubSeq(b,1,n)` to `Len(a)≤Len(b) ∧ a = SubSeq(b,1,Len(a))`, and the two are equivalent |
| v1 OrderedHistories | same; cfg 10→3 | The numbers are right, but the real event is a weaken: 13 cfgs were switched to `OrderedHistoriesV1`. The original is still checked in `MC.cfg`, `base.cfg` and `Evidence-oldOH.cfg` |
| v1 SnapshotPublishedValid | same; cfg 10→2; ev keep/keep | The numbers are right, and the event is a registration/configuration mismatch: registered as keep, in fact weaken + unchecked (see section 3) |

**Parser bug (affects all cases).** `check_annotation.properties()` (`check_annotation.py:46-63`) matches with the regex `(INVARIANTS?|PROPERT(?:Y|IES))((\s+ident)+)`. The match for INVARIANTS swallows the following `PROPERTIES X` with it, and the loop breaks when it meets the keyword PROPERTIES, so `X` is lost. I tested this: the parse result of the old `MC.cfg` does not contain `MonotoneUnlessRecovery`; `Evidence-oldMON.cfg` has only PROPERTIES, so it is parsed. There are three consequences:
1. `MonotoneUnlessRecovery` and `TraceMatched` are not in the "existing properties", so the modifications of all three arms to `MonotoneUnlessRecovery` (v0 MonotoneStep, v1 V1/Upd, v2 exemption clause) are **all uncounted**.
2. The "new: TraceMatched" of v2 is a false addition: the old `Trace.cfg:24` already has it, and only the `Trace-noinv.cfg` of v2 has just PROPERTIES. The "new: MonotoneUnlessRecovery" of v1 is also a false addition.
3. v1's `MonotoneUnlessRecoveryUpd` is actually checked in 11 cfgs, but does not appear in v1's list of new properties.

### 6.2 Verification of the earlier per-case notes (not in this repository)

| original conclusion | verification result |
|---|---|
| v0's LearnerShutdown is written as draining "following the old semantics" (`base.tla:319`) | **Partly corrected.** The old TLA has no learner exit action, and the old GracefulShutdown does not drain. The draining comes from the prose of the old brief and report, inherited verbatim (5.1) |
| v0 never read `LearnerZooKeeperServer.shutdown()` | **Verified as true.** No tool call touched this file; [136] saw the type name but did not follow it |
| Truncation essentially does not affect the conclusion | **Verified as true**, with additions: the drain semantics were fixed at minute 27; about 135 minutes were spent waiting for TLC |
| v1 and v2 "built the old worktree more systematically, and so saw the difference earlier" (inference) | **Does not hold.** Both found it by grepping subclass overrides in reconnaissance (v1 at minute 1.7, v2 at minute 9.7), and the worktree of v1 was built only at minute 46 |
| "v2 read the overlay in about 11 minutes and modeled the leak in about 23 minutes" | The real times are: 4.4 minutes reading the overlay, 9.7 minutes finding the dispatch problem, 20.1 minutes writing it into ci-context, 26.4 minutes writing it into base |
| v0 "~46 rewritten in the generation stage; ~56, ~61, ~94 weakened; MC-1 ~166; MC-2 ~208" | Real times: minute 27.2 ([94]); minutes 33.3, 37.5, 47.7; MC-1 at about minute 111 ([342]); MC-2 at about minute 191 ([428]). The conclusion "all [inv] modifications precede MC-1" does not change |
| The modification of MonotoneStep is "not recorded in the changelog" | True, but `modeling-brief.md:223` and `base.tla:1218-1220` record it. "The non-exempt branch was strengthened from comparing length to PrefixOf" holds only for committed/applied; durable still compares only length |
| v0's 7 deleted are the ActiveLeaderUniqueness rename-weakening + 6 canary renames | **Verified as true**, with the correspondence, the cfg files and the final6 witnesses added (6.1). The parser was also found to miss MonotoneUnlessRecovery |
| v1 SnapshotPublishedValid is registered as keep, but V1 is actually checked | **Verified as true** (16 regular cfgs use V1; the original is in only 2 Evidence cfgs; the oracle's 144,904 states have no violation) |
| v2 weakened only the impl-abstraction clause of MonotoneUnlessRecovery, with complete evidence and ledger | **Verified as true**, with one addition: the exemption was extended to 3 kinds of step, and E3 covers only the MODE step |
| SyncEntryJustified: v1 and v2 changed the model and kept the property | **Verified as true** (`Ev1 changelog.md:20`; `Ev2 changelog.md:20,24`) |

## 7. Uncertain and unverified points

- The change of v1's `MonotoneStepV1` to per-server quantification may strengthen or weaken the property on steps where several servers change at once. I did not verify this with TLC.
- The exemption extension of v2 to the SNAPPED and NEWLEADER steps: I did not look for a separating state for each, so I do not know whether they are necessary.
- For the 5 keep-affected properties of v0, whether they still express the same intent under the `ApplyTxn` and `FollowerCommit` that v0 rewrote: I only took a rough look and did not construct states for each.
- The indirect effect of the overlay on the exploration paths of v1 and v2 (for example, making the agent pay more attention to "old/new comparison"): single sample, cannot be judged.
- For the reproductions of v1 and v2 (v1 thread-count test FAIL on the new code and PASS on the old code; v2 `syncAlive`), I only checked the text of `confirmation-MC-1.md:13-16` and `Ev2/.../bug-report.md:57`, and did not rerun them.
- In `Av2`, between L318 and L552 there are about 5 minutes with only thinking events (the thinking is redacted), so why v2 went to look up subclass overrides can only be inferred from the sentence at [63].
