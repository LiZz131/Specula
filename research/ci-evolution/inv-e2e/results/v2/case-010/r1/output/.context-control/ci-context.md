# CI context handoff (case-010, incremental)
- Source: artifact git HEAD b16ba71 "update" over f8533cd "baseline". Diff: Learner.shutdown -> zk.shutdown(syncMode==SNAP); ZooKeeperServer.shutdown(bool) clears zkDb when !canShutdown && fully; new test testDiffSyncAfterSnap.
- Disposition (Ch.1): MODEL_CHANGE_REQUIRED (prior CompleteLearnerSync atomic; no in-memory-vs-disk DB state; no learner-abort action).
- Candidate A (sibling, pre-existing, not fixed): TRUNC sync (Learner.java snapshotNeeded=true -> writeToTxnLog=false) applies COMMITs in memory pre-NEWLEADER; abort before NEWLEADER takeSnapshot leaves in-memory db ahead of disk; syncMode=TRUNC => fully=false => db reused => DIFF rejoin => log gap.
- Candidate B (update-introduced): Learner.shutdown now calls ZooKeeperServer.shutdown(boolean); LearnerZooKeeperServer/ObserverZooKeeperServer override only shutdown() which also calls syncProcessor.shutdown(); so running learner's SyncRequestProcessor is not drained/stopped (leak, late async flush after re-sync).
- Prior harness patch = schema-v1 probes only (stateful v2 probe not preserved; harness/src empty). Record as provenance gap.
- Plan: model vars dbInitialized, learnerStage, sessionMode, logCursor, leakedQueued; recoveryVisible = in-memory db; CodeVersion const old/new.
## Progress (after R2 repair)
- Model: base/MC/Trace/Update/UpdateProps/TraceUpdate in spec/; R2 adds LeaderDecideSync/syncPlan + syncComplete timing. SANY ok.
- Findings so far: MC-1 TRUNC abort (REPRODUCED on new code by harness/repro/SpeculaTruncAbortReproTest: node lost after restart); MC-2 leaked SyncRequestProcessor (update-introduced; syncAlive=true observed in all new traces, false in old).
- Old control: diff test fails on old code (node 0 should exist); old trace -> OrderedHistories @198, UpdIdle @169.
- Pending: re-collect traces (harness/run-all.sh), revalidate all, rerun MC campaigns (round-1 provisional in spec/output/mc/provisional-r1), redo E3 evidence path, write bug-report/findings/verification-summary/final.
## Progress (R2 final model; campaigns running)
- R2 traces (4 fresh + repro new/old + old control) validated; controls rejected; evidence JSON updated (E3 trace-sourced).
- Done MC: MC-standard exhaustive (344,442 states, depth 53, no error); focused new -> MC-2 (depth 35); focused-txn1 -> MC-1 precursor (depth 38); focused/snapfix old -> SNAP violation (old control); leak-old -> pre-UPTODATE pre-existing leak variant (depth 42).
- Running: update-full, snapfix-new (30m), e2e-* BFS (30m), sims (20m), then open/discharge/canaries/hunts (batch B).
- Written: bug-report.md, findings.json, final-result.json (specula CLI absent), validation-handoff.md, brief-coverage, analysis/brief/instrumentation docs.
- TODO: verification-summary.md, final-response.json, restore artifact src (git checkout), remove work-old worktree, clean /dev/shm.
