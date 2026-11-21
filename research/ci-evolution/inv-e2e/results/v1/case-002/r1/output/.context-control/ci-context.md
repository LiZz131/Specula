# CI context handoff (case-002, incremental ZooKeeper Zab)

## Identity
- artifact: /work/current/.specula-output/artifact (git: baseline 1414ebf, update 2efbdfc)
- prior suite: /work/previous/.specula-output (immutable). current: /work/current/.specula-output
- Maven repo warmed (build-warmup-uninstrumented-new.log, exit 0). MAVEN_OPTS=-Dmaven.repo.local=/work/.cache/m2. JDK21.
- No `specula` CLI; /work/tools/start_background.sh needs missing run_model_check.sh -> run TLC directly with `timeout`.

## Update (diff)
- Learner.syncWithLeader NEWLEADER case now: setCurrentEpoch -> writeToTxnLog=true -> sock timeout -> setSyncMode(NONE)
  -> zk.startupWithoutServing() (state INITIAL) -> fzk.logRequest(packetsNotCommitted) (ASYNC enqueue to SyncRequestProcessor)
  -> clear -> writePacket(ACK NEWLEADER). After UPTODATE: ack, zk.startServing() (RUNNING), then post-NEWLEADER logRequest + commits.
- ZooKeeperServer: startup() split into startupWithServerState(RUNNING|INITIAL), startServing().
- Test DIFFSyncConsistencyTest added (3 nodes, inject SocketTimeout at UPTODATE, restart, check /zkX survives).

## Analysis conclusions (source evidence)
- M1: NEWLEADER ACK (and setCurrentEpoch) still precede fsync of DIFF txns: logRequest -> SyncRequestProcessor.processRequest just enqueues
  (SyncRequestProcessor.java run/flush); FileTxnLog append is buffered until commit(). Process crash after ACK loses them; leader
  activates (Leader.waitForNewLeaderAck -> startZkServer serves loaded DB = all logged history) -> committed txn loss.
- M3 variant: setCurrentEpoch(newEpoch) persisted before DIFF history durable -> restarted follower with new epoch & short log wins FLE (peerEpoch first).
- M2: failure between NEWLEADER and UPTODATE leaves zk in INITIAL; LearnerZooKeeperServer.shutdown canShutdown() false -> no fastForwardDataBase,
  processors leak; vote uses in-memory DB (QuorumPeer.getLastLoggedZxid -> dataTree lastProcessedZxid) lacking DIFF txns (applied only after UPTODATE).
  Pre-existing in old code too (old: nothing logged). Not fixed by update.
- Liveness-only note: SendAckRequestProcessor proposal ACKs may now precede NEWLEADER ACK; LearnerHandler treats first ACK as NEWLEADER ack.
- Requirement evidence: zookeeperInternals.md:119 "Acknowledgement means the server has recorded the proposal to persistent storage";
  ~lines 190-200 NEWLEADER rules; summary "uncommitted proposals ... committed by that leader before it becomes active"; new code comment
  Learner.java:748; DIFFSyncConsistencyTest assertions/comments.
- Prior model defects: CompleteSync installs durable atomically for DIFF; LeaderBroadcast counts followers in broadcast instead of NEWLEADER acks;
  leader never commits loaded history at activation; Trace.tla never calls base actions (projection replay).

## Plan / decisions
- Disposition: MODEL_CHANGE_REQUIRED (atomicity/ordering of DIFF logging vs NEWLEADER ACK; startup split).
- New reference: applied = in-memory data tree (vote + leader history); durable = persisted log; new vars syncBuf, syncCommits,
  nlAckSent, nlAcks, zkState, epochAcked; messages kind "nlack"; split election/discovery/sync/NEWLEADER/UPTODATE actions to probe points.
- Update props: CommittedPersistedOnQuorum (A1), LeaderCompleteness (A2).
- Harness: rebase prior patch onto artifact; move BroadcastReady after startServing; CommitDelivered before commitProcessor.commit;
  add probes ZkStartup, NewLeaderAckSent, UpToDateReceived, NewLeaderAckReceived, LeaderProposed, LeaderCommitted, AckReceived, config line.
- Scenarios: prior 4 + DIFFSyncConsistencyTest.

## Progress (2026-11-18 ~20:15Z)
- Generation done: spec/base.tla (30 vars), MC.tla, Update.tla (+UpdateProps.tla), cfgs, Trace.tla/cfg, instrumentation-spec.md; brief updated (§8 Scenarios 5,6; CR-A, CR-B).
- Harness rebased (harness/run.sh, patches/instrumentation.patch). Run 2 traces (5 scenarios incl. diff-sync-consistency) all pass action-based Trace
  with TraceMatched (ledger spec/output/trace-suite-final1.ndjson). Run-1 traces superseded (probe timing); V0 traces in traces/archived-v0 (superseded).
- Negative controls (traces/negative-controls) all rejected.
- Trace evidence: A1 violated on real diff-sync trace at event 94 (spec/evidence/trace-A1). Old props evaluated on traces (TraceOldPropsEvidence).
- Constructed evidence spec/evidence/E-*/ (tools/make_evidence.py) all as claimed.
- MC: shakedown MC.cfg ok (3min). A1 cex Update-concrete (output/mc-shakedown-concrete.log, 20 states).
  A2 cex from FocusInit2 (output/mc-hunt-A2-from-focus2.log, INITIAL-failure variant, no crash).
  Running: hunt-A2-crash-variant (ACTION_CONSTRAINT NoInitialStateFailure).
- TODO: formal campaigns (MC.cfg 30m, Update-full BFS+sim, open+discharge, reach canary FocusInit, V0 scenario hunts, final full),
  invariant-evidence.json, findings.json, bug-report.md, analysis-report, brief-coverage, changelog, provenance, final-response.json.

## Progress (2026-11-18 ~21:20Z)
- Repairs after MC/trace back-edges: fast-forward floor (Ldr:1536 marker), Outstanding/LeaderHist/Commit/FIFO current-epoch,
  SyncDiff/SyncSnap guard vs leader committed log (Case B from C1 depth 38). Final model = after 20:39:30Z.
- Trace suite final3: 6 traces pass (incl. repro). Evidence: A1 on diff-sync ev94; A2 on repro ev136.
- MC-2 REPRODUCED (updated + baseline). DIFFSyncConsistencyTest passes on baseline too (non-discriminating).
- Final-model runs: R1 MC.cfg BFS 43.2M/depth42 no viol (limited); R1s sim no viol; R3/R3b/R3c violations (A1, A2 initial, A2 crash);
  F5 full-from-focus A1 violation; canaries 8/10 BFS witnessed; Trunc tight canary running; ActivationOldEpoch witnessed via R3/F5 + trace.
- Running: F2a/F2b (Update-full BFS/sim), H-* hunts, F4a open, F4b discharge, F6 reach FocusInit sim.
- Docs written: changelog, bug-report, findings.json, invariant-evidence.json, analysis-report, brief, brief-coverage, harness README/INSTRUMENTATION.
- TODO: validation-summary.md (head written: spec/output/validation-summary.md.head + campaign_table.py), provenance (tools/make_provenance.py),
  spec/final-result.json, /work/current/final-response.json, cleanup (/dev/shm, old-control worktree keep?), final MC.cfg is R1.

## Final state (2026-11-18 ~22:35Z)
- Final reference hashed in spec/output/FINAL_MODEL_SHA256 (from 21:52:06Z). Trace suite final4: 6/6 pass.
- Final campaigns Z1-Z9 complete; violations only for update properties (Z3, Z3b, Z3c, Z4a, Z5); canaries witnessed incl. exact FocusInit (Z6) and TRUNC (tight).
- Findings: MC-1 ENV_LIMITED, MC-2 REPRODUCED (spec/findings.json, spec/bug-report.md, spec/final-result.json).
- Remaining: write /work/current/final-response.json and return it.
