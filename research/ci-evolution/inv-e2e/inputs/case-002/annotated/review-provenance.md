# Provenance

Everything below was done inside `/work`. There was no network access and `git` was never run directly. Scratch scripts are in `out/tmp/`: `quotecheck.py`, `structcheck.py`, `apply_review.py` and the SANY logs.

## `tools/hist.sh` commands (all run from `/work`, in this order)

Paths are abbreviated after the first use. `ZQ` = `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum`. `OQ` = the pre-Maven path `src/java/main/org/apache/zookeeper/server/quorum`.

1. `tools/hist.sh show --stat 19d85670` (message of ZOOKEEPER-2307)
2. `tools/hist.sh show 19d85670 -- '*QuorumPeer.java'`
3. `tools/hist.sh show 19d85670 -- '*Zab1_0Test.java'`
4. `tools/hist.sh show --stat 1a556bd1` (message of ZOOKEEPER-1343)
5. `tools/hist.sh show --stat f8f15de5` (message of ZOOKEEPER-1264/1282/1291)
6. `tools/hist.sh show --stat 148c2cd6` (message of ZOOKEEPER-3104)
7. `tools/hist.sh show 148c2cd6 -- '*LearnerHandler.java'`
8. `tools/hist.sh log -S'is older than the last zxid' --oneline -- ZQ/QuorumPeer.java` → faa7cec7 (Maven move)
9. `tools/hist.sh log -S'epochOfZxid' --oneline -- ZQ/QuorumPeer.java` → faa7cec7
10. `tools/hist.sh log -S'acceptedEpoch < currentEpoch' --oneline -- ZQ/QuorumPeer.java` → faa7cec7
11. `tools/hist.sh log -S'is older than the last zxid' --oneline -- OQ/QuorumPeer.java` → faa7cec7, 776db780
12. `tools/hist.sh log -S'epochOfZxid > currentEpoch' --oneline -- OQ/QuorumPeer.java` → faa7cec7, 776db780
13. `tools/hist.sh log -S'acceptedEpoch < currentEpoch' --oneline -- OQ/QuorumPeer.java` → faa7cec7, 776db780
14. `tools/hist.sh show --stat 776db780`
15. `tools/hist.sh show 776db780 -- OQ/QuorumPeer.java`, piped through `grep` for added comment lines (only "load the epochs" and "pick a reasonable epoch number")
16. `tools/hist.sh log -S'toFlush' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java src/java/main/org/apache/zookeeper/server/SyncRequestProcessor.java` → 5cb10bb5, cc431f70, 876aaf42, 293386c3, 2a23a259, 67c653cf
17. `tools/hist.sh show 876aaf42`, piped through `grep -i` for order/fsync/before (no ordering rule)
18. `tools/hist.sh show cc431f70`, piped through `grep -i` for order/fsync/before (no ordering rule)
19. `tools/hist.sh log -S'packetsCommitted' --oneline -- ZQ/Learner.java OQ/Learner.java` → adedc7a4, f8f15de5

I also read `tools/hist.sh` itself with `cat` but did not run it without arguments.

## Files read

### Task and model files

- `/work/ANNOTATION-RULES.md`
- `/work/tools/hist.sh`
- `spec-original/`: all 7 `.cfg` files in full. `MC.tla`, `Trace.tla` and `base.tla` were read through `diff` against `spec-annotated/` and a comment-stripped comparison.
- `spec-annotated/`: `MC.tla`, `Trace.tla` and `base.tla` in full. The `.cfg` files were compared with `cmp` (identical).
- `out/spec-reviewed/`: all files (generated, then checked).

### Source files, under `/work/source/`

Line ranges were read by hand. In addition, `out/tmp/quotecheck.py` opened every cited file at its cited line ±3.

- `zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md`: 40-300
- `zookeeper-docs/src/main/resources/markdown/zookeeperAdmin.md`: 2580-2605
- `zookeeper-docs/src/main/resources/markdown/zookeeperOver.md`: 155-180
- `zookeeper-docs/src/main/resources/markdown/zookeeperProgrammers.md`: 1160-1185
- `ZQ/Learner.java`: 480-530, 560-600, 640-680, 725-760
- `ZQ/Leader.java`: 745-770, 870-910, 1385-1425
- `ZQ/FollowerZooKeeperServer.java`: 80-125
- `ZQ/CommitProcessor.java`: 55-100
- `ZQ/QuorumPeer.java`: 1100-1160, plus `grep` for the `acceptedEpoch`/`currentEpoch` fields (2123-2132)
- `ZQ/Follower.java`: 95-125
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java`: 30-80, 150-245, plus `grep -i order`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java`: 455-480
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnLog.java`: `grep -i order` only
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/TxnLog.java`: 75-95
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java`: 585-610
- `ZQ/ProposalRequestProcessor.java` and `ZQ/SendAckRequestProcessor.java`: `grep -i order` only
- `zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java`: 180-225, 585-665, 720-790
- `zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/QuorumPeerMainTest.java`: 1100-1200, plus `grep` for the test name (line 1040)
- `zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/EpochWriteFailureTest.java`: `grep` for assert/epoch lines
- `zookeeper-server/src/test/java/org/apache/zookeeper/test/FollowerResyncConcurrencyTest.java`: 562-615, plus `grep`/`awk` for method boundaries (verifyState at 562; callers at 326 and 485)
- `zookeeper-server/src/test/java/org/apache/zookeeper/test/TruncateTest.java`: 140-240
- Whole `source/` tree: `grep -rIl -E 'SyncSelected|TxnDurable|BroadcastReady'` and `grep -rIil ndjson` (to repeat the TraceMatched note's search; no matches)
