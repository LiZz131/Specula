# Provenance

Every `tools/hist.sh` command and every file I read during this review. All work used only `/work`. No network access was used, and `git` was never run directly: all history access went through `/work/tools/hist.sh`, mostly via a logging wrapper (`/work/out/tmp/h.sh`, which calls `exec /work/tools/hist.sh "$@"`).

## `tools/hist.sh` commands (in order)

Quoting is restored here; the raw log is in `out/tmp/hist-commands.log`. "(head)" means the output was cut with `head` or `grep` while I read it.

1. `tools/hist.sh` (no arguments; prints usage)
2. `tools/hist.sh show --stat f8f15de5` (head)
3. `tools/hist.sh show --stat b978dfb9` (head)
4. `tools/hist.sh show --stat 27d045af` (head)
5. `tools/hist.sh show f8f15de5 -- '*Leader.java' '*Learner.java'` (head)
6. `tools/hist.sh log -S'acceptedEpoch < currentEpoch' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java src/java/main/org/apache/zookeeper/server/quorum/QuorumPeer.java` → 776db780
7. `tools/hist.sh show 776db780` (head)
8. `tools/hist.sh show 776db780 -- src/java/main/org/apache/zookeeper/server/quorum/QuorumPeer.java` (grep for the epoch hunk)
9. `tools/hist.sh show 1ea6879b` (head)
10. `tools/hist.sh log -1 --format='%h %ad %s' --date=short <c>` for c in cc900a3b 21ef61aa 9531ec29 8b4520f7 67c653cf 0254f868 344a3079 0957b840 3dc91bd2 9f102d31. I misused these: hist.sh prefixes `base`, so each printed the base commit. They were superseded by item 14.
11. `tools/hist.sh log -S'Not sufficient followers synced' --oneline` → 8b4520f7, 9531ec29, 21ef61aa
12. `tools/hist.sh log -S'enum ZabState' --oneline` → cc900a3b
13. `tools/hist.sh log -S'setZabState(ZabState.ELECTION)' --oneline` → cc900a3b
14. `tools/hist.sh show -s --format='%h %ad %s' --date=short <c>` for c in cc900a3b 21ef61aa 9531ec29 8b4520f7 67c653cf 0254f868 344a3079 0957b840 3dc91bd2 9f102d31 776db780 1ea6879b
15. `tools/hist.sh log -S'callbacks will be' --oneline` → e5fc1228, d6a12a80, f813b639, 047d9258
16. `tools/hist.sh log -S'makeSnapshotName(lastZxid)' --oneline` → 0254f868
17. `tools/hist.sh log -S'we need to truncate the log to the lastzxid of the leader' --oneline` → 0957b840, 344a3079
18. `tools/hist.sh log -S'Leader.TRUNC' --oneline` → a4bc9857, e5fc1228, 44d27361, 5847d0d1, 9f102d31, 27d045af, 0957b840, 344a3079
19. `tools/hist.sh log -S'callbacks will be' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java src/java/main/org/apache/zookeeper/server/SyncRequestProcessor.java src/java/main/com/yahoo/zookeeper/server/SyncRequestProcessor.java` → 67c653cf, daa66b7c, be031cb4
20. `tools/hist.sh log --follow -S'callbacks will be' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java` → 047d9258 (initial import)
21. `tools/hist.sh log -S'truncateLog' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java` → faa7cec7
22. `tools/hist.sh log -S'deserializeSnapshot' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java` → faa7cec7
23. `tools/hist.sh show a4bc9857` (head)
24. `tools/hist.sh log -i --grep='two leaders\|multiple leaders\|split brain\|split-brain\|more than one leader' --oneline` → a4bc9857
25. `tools/hist.sh log -S'syncedAckSet' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java` → faa7cec7
26. `tools/hist.sh log -S'is less than the current epoch' --oneline` → 1ea6879b
27. `tools/hist.sh log -S'setAcceptedEpoch' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java src/java/main/org/apache/zookeeper/server/quorum/Learner.java` → 776db780
28. Items 19 and 20 run again separately, because their first outputs ran together; the results above are from the re-run
29. `tools/hist.sh log --follow -S'truncateLog' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java` → 0957b840
30. `tools/hist.sh log --follow -S'deserializeSnapshot' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java` → 3dc91bd2, 0957b840 (confirms the MonotoneUnlessRecovery note)

## Files read

Workspace and model:
- `/work/ANNOTATION-RULES.md` (whole)
- `/work/tools/hist.sh` (whole)
- `/work/spec-annotated/`: `base.tla`, `MC.tla`, `Trace.tla` (whole) and all 16 `.cfg` files (whole)
- `/work/spec-original/`: `base.tla`, `MC.tla`, `Trace.tla` and all 16 `.cfg` files, compared by `diff`/`cmp` with the annotated and reviewed copies
- `/work/out/`, `/work/out/tmp/`, `/work/tools/network-guard/`: directory listings only; `/work/.cache/`: file names listed with `find`, no contents read
- `/work/lib/tla2tools.jar`, `/work/lib/CommunityModules-deps.jar`: executed for SANY only

Source tree (`/work/source/`; line ranges read):
- `zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md`: 40-300
- `zookeeper-docs/src/main/resources/markdown/zookeeperAdmin.md`: 2590-2625, 1840-1852
- `zookeeper-docs/src/main/resources/markdown/zookeeperReconfig.md`: 545-558
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java`: 640-668, 710-714, 758-762, 880-935, 1298-1302, 1403-1407
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java`: 481-493, 851-860, 1110-1150
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java`: 503-527, 560-600, 625-629, 661-665, 741-745 (plus `grep -n -i epoch`)
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Follower.java`: 107-111, 168-174
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java`: 74-78, 93-113
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/CommitProcessor.java`: 66-74
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerHandler.java`: 638-650, 818-836
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/SendAckRequestProcessor.java`: 40-44
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/ProposalRequestProcessor.java`: 51-55
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java`: 36-56, 77-86, 243-247
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java`: 515-525
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZKDatabase.java`: 595-625
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/TxnLog.java`: 75-102
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java`: 460-472, 502-542
- `zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/Zab1_0Test.java`: 560-680, 1105-1140 (plus `grep -n` for test names and quotes)
- `zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/DIFFSyncConsistencyTest.java`: 60-230 (plus `grep -n` for the test name)

Searches over the source tree (grep, output read):
- `grep -rn -i "accepted epoch|acceptedEpoch|currentEpoch|current epoch" --include=*.md` (no hits) and `--include=*.md --include=*.txt --include=*.html` file list (no hits)
- `grep -rn -i "two leaders|only one leader|single leader|split brain|split-brain" --include=*.java --include=*.md` (non-test files)
- For every `watch:` entry: `find source -name <File> -path '*main*'`, then a method-declaration grep in that file (to confirm each watched symbol exists)
- The check script `/work/out/tmp/check_blocks.py` reads the cited line ±2 of every `source/` evidence location (see `check.md`)
