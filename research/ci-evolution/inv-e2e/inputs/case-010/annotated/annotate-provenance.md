# Provenance

Everything below was done inside `/work`. No network access was used, `git` was not run directly, and no knowledge of later ZooKeeper versions, issues or commits was used as evidence. Every cited commit is an ancestor of `base` (`ea3042d5`, 2020-11-23) and was reached through `tools/hist.sh`.

## `tools/hist.sh` commands (complete, in order)

Commands 1-2 were run directly. Commands 3-42 went through a logging wrapper (`out/tmp/h.sh`, which writes the command to `out/tmp/hist-commands.log` and then `exec`s `tools/hist.sh` with the same arguments). The quoting below is restored; the raw log shows the same arguments without quotes.

| # | Command | Purpose / result |
|---|---|---|
| 1 | `tools/hist.sh` | usage text |
| 2 | `tools/hist.sh log -3 --format='%H %ad %s'` | base = ea3042d5 (ZOOKEEPER-3989), 2020-11-23 |
| 3 | `tools/hist.sh log --oneline -S'is less than the current epoch' -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java src/java/main/org/apache/zookeeper/server/quorum/QuorumPeer.java` | 1ea6879b |
| 4 | `tools/hist.sh log --oneline -S'acceptedEpoch < currentEpoch'` | 776db780 |
| 5 | `tools/hist.sh log --oneline -S'ACCEPTED_EPOCH_FILENAME'` | c84f7ef1, 776db780 |
| 6 | `tools/hist.sh show --stat 776db780` | Zab 1.0 commit (ZOOKEEPER-335/1081/1082) |
| 7 | `tools/hist.sh show 776db780 -- src/java/main/org/apache/zookeeper/server/quorum/QuorumPeer.java src/java/main/org/apache/zookeeper/server/quorum/Learner.java src/java/main/org/apache/zookeeper/server/quorum/Follower.java` | loadDataBase epoch checks added without a rule comment |
| 8 | `tools/hist.sh show 1ea6879b` | only the error message text was corrected |
| 9 | `tools/hist.sh log --oneline -S'enum ZabState'` | cc900a3b |
| 10 | `tools/hist.sh log --oneline -S'setZabState(ZabState.ELECTION)'` | cc900a3b |
| 11 | `tools/hist.sh show cc900a3b --stat` | ZOOKEEPER-3459 "Add admin command to display synced state of peer" |
| 12 | `tools/hist.sh show cc900a3b` | adds ZabState "(Used for monitoring)" |
| 13 | `tools/hist.sh log --oneline -S'ZOOKEEPER-3911'` | b978dfb9 |
| 14 | `tools/hist.sh log --oneline --grep='3911'` | b978dfb9, 31e92e0a |
| 15 | `tools/hist.sh show b978dfb9` | ZOOKEEPER-3911 message and diff (Learner.java, ZooKeeperServer.java, DIFFSyncConsistencyTest) |
| 16 | `tools/hist.sh log --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java src/java/main/org/apache/zookeeper/server/quorum/Learner.java` | Learner.java history list |
| 17 | `tools/hist.sh show f8f15de5 --stat` | ZOOKEEPER-1264/1282/1291 |
| 18 | `tools/hist.sh show f8f15de5 -- src/java/main/org/apache/zookeeper/server/quorum/Learner.java src/java/main/org/apache/zookeeper/server/quorum/Leader.java` | setCurrentEpoch moved to NEWLEADER; setAcceptedEpoch moved into getEpochToPropose |
| 19 | `tools/hist.sh show 0706b40a --stat` | ZOOKEEPER-2872 (no rule text) |
| 20 | `tools/hist.sh show bbfd0169 --stat` | ZOOKEEPER-2678 (no rule text) |
| 21 | `tools/hist.sh log -S'setZabState(ZabState.ELECTION)' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java` | cc900a3b |
| 22 | `tools/hist.sh log -S'truncateLog' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java src/java/main/org/apache/zookeeper/server/quorum/Learner.java` | 0957b840 |
| 23 | `tools/hist.sh log -S'deserializeSnapshot' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java src/java/main/org/apache/zookeeper/server/quorum/Learner.java` | 3dc91bd2, 0957b840 |
| 24 | `tools/hist.sh log -S'makeSnapshotName(lastZxid)' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java src/java/main/org/apache/zookeeper/server/persistence/FileTxnSnapLog.java` | 0254f868 |
| 25 | `tools/hist.sh log -S'Not sufficient followers synced' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java src/java/main/org/apache/zookeeper/server/quorum/Leader.java` | 8b4520f7, 9531ec29, 21ef61aa |
| 26 | `tools/hist.sh log -S'callbacks will be' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java src/java/main/org/apache/zookeeper/server/SyncRequestProcessor.java` | 67c653cf (package move) |
| 27 | `tools/hist.sh log -S'truncateLog' --oneline -- src/java/main/org/apache/zookeeper/server/quorum/Follower.java src/java/main/com/yahoo/zookeeper/server/quorum/Follower.java` | 0957b840, 67c653cf, daa66b7c, be031cb4 (output first appeared interleaved with #28; re-run as #40) |
| 28 | `tools/hist.sh log -S'Lost quorum' --oneline` | 047d9258 (re-run as #41) |
| 29 | `tools/hist.sh show 047d9258 --stat` | initial import file list |
| 30 | `tools/hist.sh grep -n -i truncat 047d9258 -- '*Follower.java' '*TxnLog*.java'` | no matches |
| 31 | `tools/hist.sh log -S'Leader.TRUNC' --oneline` | a4bc9857, e5fc1228, 44d27361, 5847d0d1, 9f102d31, 27d045af, 0957b840, 344a3079 |
| 32 | `tools/hist.sh log -S'we need to truncate the log to the lastzxid of the leader' --oneline` | 0957b840, 344a3079 |
| 33 | `tools/hist.sh show --stat a4bc9857` | ZOOKEEPER-3701 "Split brain on log disk full" (no rule used) |
| 34 | `tools/hist.sh show --stat 27d045af` | ZOOKEEPER-1154/1156 message |
| 35 | `tools/hist.sh show 27d045af -- src/java/main/org/apache/zookeeper/server/quorum/LearnerHandler.java src/java/main/org/apache/zookeeper/server/persistence/FileTxnLog.java` | TRUNC-on-first-packet comments ("Does the peer have some proposals that the leader hasn't seen yet") |
| 36 | `tools/hist.sh show 8b4520f7 -- src/java/main/org/apache/zookeeper/server/quorum/Leader.java` | ZOOKEEPER-1324; removed comment "Followers aren't syncing fast enough, renounce leadership!" (not a uniqueness rule) |
| 37 | `tools/hist.sh show -s --format=%B f8f15de5` | message dump for quote verification |
| 38 | `tools/hist.sh show -s --format=%B b978dfb9` | message dump for quote verification |
| 39 | `tools/hist.sh show -s --format=%B 27d045af` | message dump for quote verification |
| 40 | `tools/hist.sh log -S'truncateLog' --oneline -- src/java/main/org/apache/zookeeper/server/quorum/Follower.java src/java/main/com/yahoo/zookeeper/server/quorum/Follower.java` | re-run of #27: 0957b840, 67c653cf, daa66b7c, be031cb4 |
| 41 | `tools/hist.sh log -S'Lost quorum' --oneline` | re-run of #28: 047d9258 |
| 42 | `tools/hist.sh grep -n -i truncat 047d9258 -- '*Follower.java' '*TxnLog*.java'` | re-run of #30: no matches |

History evidence actually cited in the model: f8f15de5 (message, ×2), b978dfb9 (message), 27d045af (message). History mentioned only in `note:` / `clause` lines: 776db780, 1ea6879b, cc900a3b, 21ef61aa, 9531ec29, 8b4520f7, 67c653cf, 0254f868, 0957b840, 3dc91bd2, 9f102d31, 344a3079.

## Files read

### Model (`/work/spec-original/`)
- `base.tla`, `MC.tla`, `Trace.tla`: read in full.
- All 16 `.cfg` files: read in full (`MC*.cfg`, `Trace.cfg`, `base.cfg`, `base-wide.cfg`).

### Tools
- `/work/tools/hist.sh`: read in full. `/work/tools/network-guard/` and `/work/lib/`: listed only.

### Source (`/work/source/`), with the line ranges read
Documentation:
- `zookeeper-docs/src/main/resources/markdown/zookeeperInternals.md`: 1-330.
- `zookeeper-docs/src/main/resources/markdown/zookeeperAdmin.md`: 2575-2650.
- Directory listing of `zookeeper-docs/src/main/resources/markdown/`.

Main code (`zookeeper-server/src/main/java/org/apache/zookeeper/server/`):
- `quorum/Learner.java`: 60-140, 440-897.
- `quorum/Follower.java`: 60-293.
- `quorum/FollowerZooKeeperServer.java`: 40-184.
- `quorum/SendAckRequestProcessor.java`: 30-81.
- `quorum/AckRequestProcessor.java`: 25-57.
- `quorum/ProposalRequestProcessor.java`: 30-100.
- `quorum/CommitProcessor.java`: 36-110.
- `quorum/Leader.java`: 60-130, 240-330, 560-800, 850-1100, 1180-1600.
- `quorum/QuorumPeer.java`: 470-520, 840-925, 1095-1170, 2118-2180, plus a grep for epoch/ZabState identifiers.
- `quorum/LearnerHandler.java`: 440-800, 800-870, 975-1010, plus a grep for TRUNC.
- `SyncRequestProcessor.java`: 40-281.
- `ZKDatabase.java`: 284-304, 599-628.
- `ZooKeeperServer.java`: 500-545.
- `persistence/FileTxnSnapLog.java`: 228-290, 317-344, 452-524.
- `persistence/TxnLog.java`: 25-140.
- `persistence/SnapShot.java`: 25-72.
- Directory listing of `quorum/`.

Tests (`zookeeper-server/src/test/java/org/apache/zookeeper/`):
- `server/quorum/Zab1_0Test.java`: 130-300, 505-935, 1070-1234.
- `server/quorum/EpochWriteFailureTest.java`: 20-154.
- `server/quorum/DIFFSyncConsistencyTest.java`: 118-124, 150-294.
- `server/quorum/FuzzySnapshotRelatedTest.java`: 60-80.
- Directory listing of `server/quorum/`.

Searches (grep):
- docs for `zab`, `acceptedEpoch|accepted epoch|currentEpoch|current epoch`, `fuzzy`;
- `src/main` for `accepted epoch|current epoch`;
- tests for `ACCEPTED_EPOCH_FILENAME|CURRENT_EPOCH_FILENAME|setAcceptedEpoch|setCurrentEpoch` and `getZxidFromName|makeSnapshotName`;
- whole source tree for Zab paper references and PDFs (none found).

## Scratch files (`/work/out/tmp/`)
- `h.sh`, `hist-commands.log`: history logging wrapper and its log.
- `annotate.py`: inserts the comment blocks (only `\* ` lines; aborts on any other line).
- `check_evidence.py`, `msgs/*.txt`: evidence checker and commit-message dumps.
- `sany-*.log`: SANY output.
- `tlc/`: scratch copies of `MC.tla`, `base.tla`, `MC-full.cfg`, plus the steering modules `Scn.tla`/`Scn2.tla` and their configs and logs. These are used only for `concerns.md` C1/C2 and are not part of the deliverable.
- `scn2-counterexample.log`: the TLC trace for C1.
