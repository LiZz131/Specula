# CI context (run-local working memory) — case-002 ZooKeeper Zab incremental

## Identity
- old = artifact commit 1414ebf (baseline), new = 2efbdfc (update). Changed: ZooKeeperServer.startup split
  (startupWithoutServing=INITIAL / startServing=RUNNING), Learner.syncWithLeader NEWLEADER now: setSoTimeout,
  setSyncMode(NONE), zk.startupWithoutServing(), fzk.logRequest(all packetsNotCommitted), clear, THEN ACK NEWLEADER.
  After UPTODATE: writePacket(ack); zk.startServing(); log remaining pending; commit packetsCommitted.
- Work copy for harness: harness/build/work-source (git init'ed, old patch applied except BroadcastReady hunk).

## Disposition: MODEL_CHANGE_REQUIRED (decided). Plus repairs of prior model defects:
- prior CompleteSync made DIFF history instantly durable; prior LeaderBroadcast counted followers in broadcast
  (after UPTODATE) instead of NEWLEADER ACKs; prior model never committed leader's recovered log; votes/sync used
  durable log instead of data tree (QuorumPeer.getLastLoggedZxid = zkDb.getDataTreeLastProcessedZxid, :1257).
- prior Trace.tla is observation-stepping (does not call base actions).

## Candidate defects from code reading (new code)
- G1: ACK NEWLEADER sent after logRequest (async SyncRequestProcessor queue) but before fsync -> crash after ACK loses
  txns the leader counted (Leader starts serving after NEWLEADER quorum, Leader.java:661-688).
- G2: failure between NEWLEADER and UPTODATE: zk state INITIAL -> LearnerZooKeeperServer.shutdown (:155) and
  ZooKeeperServer.shutdown (:803) return early (canShutdown requires RUNNING/ERROR) -> no fastForwardDataBase, sync
  processor leaked (still flushes). Data tree stale vs log; vote/FOLLOWERINFO zxid = tree; Leader.lead loadData uses
  initialized tree (ZooKeeperServer.java:480-503). In-process re-election among such followers loses the txn served
  by old leader. Also DIFF re-sent from stale zxid -> duplicate log entries (FileTxnLog.append warns only).
- G3 (liveness, CR only): SendAckRequestProcessor started at NEWLEADER can emit ACK(zxid) before NEWLEADER ACK;
  LearnerHandler treats first ACK as NEWLEADER ack (:611-623), Leader.waitForNewLeaderAck rejects mismatched zxid.
- Leader order: startZkServer (RUNNING) then setZabState(BROADCAST) (Leader.java:688 / :712).

## Plan
- New base vars: pending, syncCommits, zkState, learnerStep, nlAcks, maxCommitted(ghost); Entry gets ctr.
- Actions: ServerShutdown (fast-forward only if RUNNING), SyncWithLeader(s,mode), LearnerNewLeaderPersist,
  LearnerNewLeaderStartup, LearnerLogPendingOne, LearnerSendNewLeaderAck, LearnerUptodate, LeaderStartZkServer,
  LeaderEnterBroadcast, Restart(tree:=restore).
- Update.tla: LeaderCompleteness / NewLeaderAckDurable etc.
- New probes: SyncProposalBuffered, SyncCommitBuffered, NewLeaderAckSent(aux pending/committed), UptodateReceived,
  ZkServerState, ZkShutdownSkipped/ZkShutdownStarted/FastForwarded, NewLeaderAckCounted/Rejected, NewLeaderQuorum.
- Scenario add: DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog (from diff).

## Progress (after validation gate)
- Generation done: base.tla rewritten (sync buffer, NEWLEADER split into Persist/Startup/LogPendingOne/SendAck,
  UPTODATE split into StartServing/LogOne/CommitOne/EnterBroadcast, LeaderStartZkServer/EnterBroadcast,
  ServerShutdown w/ canShutdown guard, Restore/FastForward/TruncateLog, treeFloor, ghosts maxCommitted/ackedHist).
  MC.tla, Update.tla (Affected/Interaction/EnvUpdate/FocusInit(PROVISIONAL: must match witness)), cfgs written.
- Harness: harness/run.sh rebased (patch regenerated from pristine archive; work tree has no .git).
  Fresh traces (attempt 5): follower-snap 27, follower-diff 27, quorum 89, leader-abandon 349, diff-sync 185.
- Trace validation: all 5 PASS with final Trace.tla (spec/output/trace-final-*.log); 3 mutants rejected.
- Repairs from trace: OneActiveLeaderPerEpoch refined (leadersByEpoch), probe CommitDelivered moved before
  hand-off, trace-interpretation for ACK ordering / SNAP select / implied leader propose.
- Superseded attempt3 diff-sync trace shows real in-process re-election of stale-tree s1 as epoch-3 leader.
## Next: MC campaigns (MC.cfg, Update-full, witness->FocusInit, focus, open, discharge, hunts), findings.

## Progress (MC + findings) — 08:40Z
- Repairs during MC: vote lifetime (ForgetVotes/consume), FastForward from LastLogged (found via repro trace).
- Final artifacts sha in spec/output/final-candidate-sha256.txt; final trace regression 6/6 PASS (trace-final2-*).
- Findings: MC-1 (U-1 ACK before fsync, cex mc-final-hunt-crash-window-bfs, ENV_LIMITED repro),
  MC-2 (U-2 stale tree re-election, cex mc-final-hunt-reelection-bfs, REPRODUCED new+old via harness/repro),
  MC-3 (TRUNC(0) keeps entry, cex mc-final-focus-trunc-bfs, REPRODUCED learner-side), CR-1 availability.
- Written: bug-report.md, findings.json, modeling-brief.md, analysis-report.md, brief-coverage.md,
  validation-handoff.md, changelog.md (needs MC rounds appended), harness docs.
- Pending: final campaign stats -> spec/output/campaign-summary.md; provenance-manifest.json;
  spec/final-result.json; /work/current/final-response.json; cleanup /dev/shm; no bg procs.
