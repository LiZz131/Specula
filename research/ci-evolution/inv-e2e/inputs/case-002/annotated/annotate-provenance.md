# Provenance

Everything here was gathered from `/work` only. I did not use the network or run `git`
directly. History came only from `/work/tools/hist.sh`. Scratch files are in `/work/out/tmp/`.

## 1. Every `tools/hist.sh` command run (in order)

Commands were run from `/work` as `tools/hist.sh ...`. Some outputs were piped through
`head`/`grep`/`tr` for reading; the pipe is noted where it filtered content.

| # | Command | Purpose / result |
|---|---|---|
| 1 | `hist.sh` (no arguments) | usage text (exit 2) |
| 2 | `hist.sh log -3 --format='%H %ad %s'` | base = 33bf3645 (2020-11-12, ZOOKEEPER-3839) |
| 3 | `hist.sh log -S'is less than the current epoch' --oneline -- zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/QuorumPeer.java src/java/main/org/apache/zookeeper/server/quorum/QuorumPeer.java` | 1ea6879b |
| 4 | `hist.sh log -S'acceptedEpoch < currentEpoch' --oneline` | 776db780 |
| 5 | `hist.sh log -S'epochOfZxid > currentEpoch' --oneline` | 776db780 |
| 6 | `hist.sh show 776db780 --stat` | ZOOKEEPER-335/1081/1082 file list |
| 7 | `hist.sh show 776db780 -- src/java/main/org/apache/zookeeper/server/quorum/QuorumPeer.java src/java/main/org/apache/zookeeper/server/quorum/Learner.java src/java/main/org/apache/zookeeper/server/quorum/Leader.java` (piped to `grep` for added/removed comment lines) | origin of the Learner "we cannot ack" comment |
| 8 | `hist.sh log --oneline -i --grep='currentEpoch\|current epoch\|NEWLEADER'` | 19d85670, 148c2cd6, 8b4520f7, 21ef61aa, f8f15de5, 776db780 |
| 9 | `hist.sh show 19d85670` (first 150 lines) | ZOOKEEPER-2307 message and diff (QuorumPeer setters, EpochWriteFailureTest) |
| 10 | `hist.sh show f8f15de5 --stat` | ZOOKEEPER-1264/1282/1291 |
| 11 | `hist.sh show f8f15de5 -- src/java/main/org/apache/zookeeper/server/quorum/Learner.java src/java/main/org/apache/zookeeper/server/quorum/Leader.java` (first 200 lines) | setCurrentEpoch moved to NEWLEADER; setAcceptedEpoch moved into getEpochToPropose |
| 12 | `hist.sh show 148c2cd6` (first 120 lines) | ZOOKEEPER-3104 message and Leader.java diff |
| 13 | `hist.sh show 148c2cd6 -- src/java/main/org/apache/zookeeper/server/quorum/LearnerHandler.java` (piped to `grep '^[-+]'`) | NEWLEADER send moved after snapshot |
| 14 | `hist.sh show 148c2cd6 --stat` | Leader.java, LearnerHandler.java, QuorumPeerMainTest.java |
| 15 | `hist.sh log -S'truncateLog(' --oneline` | a4bc9857, 6abd8593, 43eedab1, 3ba0a545, 0957b840, 0254f868, 344a3079 |
| 16 | `hist.sh log -S'Not able to truncate the log' --oneline` | 0957b840, 0254f868, 344a3079 |
| 17 | `hist.sh log -S'get in sync with the' --oneline` | 0957b840, 0254f868, 344a3079 |
| 18 | `hist.sh log -S'Cannot send TRUNC to peer' --oneline` | 9f102d31 |
| 19 | `hist.sh show a4bc9857` (first 150 lines) | ZOOKEEPER-3701 truncate failure handling |
| 20 | `hist.sh show 43eedab1 --stat` | ZOOKEEPER-1489 file list |
| 21 | `hist.sh show 43eedab1 -- src/java/main/org/apache/zookeeper/server/persistence/FileTxnLog.java` | empty (the commit did not touch that path) |
| 22 | `hist.sh log -S'fuzzy' --oneline` | 2805e898, ee04684b, 46b2018d, bc24f7c0, e5fc1228, d6a12a80, 6651a126, e501d9cc, f813b639 (messages only read) |
| 23 | `hist.sh show 1ea6879b` (first 60 lines) | ZOOKEEPER-2279 error-message fix |
| 24 | `hist.sh show 776db780 -- src/java/main/org/apache/zookeeper/server/quorum/QuorumPeer.java` (first 140 lines) | original loadDataBase epoch checks, no explanatory comment |
| 25 | `hist.sh log -S'lastAcceptedEpoch >= epoch' --oneline` | 1a556bd1 (run twice; the first run's output was interleaved with #26) |
| 26 | `hist.sh log -S'we cannot ack' --oneline` | 776db780 (run twice, as above) |
| 27 | `hist.sh show 1a556bd1 --stat` | ZOOKEEPER-1343 message, file list |
| 28 | `hist.sh log -1 --format=%B 1a556bd1`, `... 19d85670`, `... f8f15de5`, `... 148c2cd6` (each piped to `tr`/`grep -F`) | **mistaken**: `hist.sh log` always starts at `base`, so each returned base's message; nothing was used |
| 29 | `hist.sh log -1 --format=%B 1a556bd1 \| head -3` and `hist.sh log -1 --format='%B' 1a556bd1 \| od -c \| head -5` | debugging #28; confirmed it shows base's message |
| 30 | `hist.sh show -s --format=%B 1a556bd1`, `... 19d85670`, `... f8f15de5`, `... 148c2cd6` (piped to `tr`/`grep -F`) | verified that each cited history quote appears in the commit message |

A machine log of most of these is in `out/tmp/histlog.txt`. The table above is the complete
list; the log file omits the second runs of #25/#26 and the mistaken #28/#29.

## 2. Files read

### Workspace / model
- `/work/tools/hist.sh` (whole file)
- `/work/spec-original/*.cfg` (all 7, whole files)
- `/work/spec-original/base.tla`, `MC.tla`, `Trace.tla` (whole files)
- `/work/lib/tla2tools.jar`, `/work/lib/CommunityModules-deps.jar` (only executed, for SANY)

### Documentation (`source/zookeeper-docs/src/main/resources/markdown/`)
- `zookeeperInternals.md` lines 1-330 (Atomic Broadcast, Consistency, Quorums)
- `zookeeperOver.md` lines 155-176 (Guarantees)
- `zookeeperProgrammers.md` lines 1145-1195 (consistency guarantees)
- `zookeeperAdmin.md` lines 2570-2605 (data directory / fuzzy snapshots)
- `grep` across all `*.md` for `acceptedEpoch|currentEpoch`, `fuzzy|idempotent`,
  `will persist|older view|Sequential Consistency|Single System Image|Reliability|Atomicity|Timeliness`,
  `one leader|single leader|two leaders|multiple leaders|same epoch|unique epoch`

### Main sources (`source/zookeeper-server/src/main/java/org/apache/zookeeper/server/`)
- `quorum/Leader.java` lines 425-440, 570-800, 860-1060, 1200-1300, 1330-1600 (plus grep)
- `quorum/Learner.java` lines 470-820 (plus grep)
- `quorum/Follower.java` lines 60-140, 160-200
- `quorum/LearnerHandler.java` lines 440-620, 760-1045 (plus grep)
- `quorum/QuorumPeer.java` lines 1085-1160, 2115-2180 (plus grep for epoch handling, SyncMode/ZabState)
- `quorum/FastLeaderElection.java` lines 705-745 and 985-1003 (grep context)
- `quorum/FollowerZooKeeperServer.java` lines 74-122
- `quorum/ProposalRequestProcessor.java` lines 29-95 and comment grep
- `quorum/SendAckRequestProcessor.java`, `quorum/AckRequestProcessor.java` (comment grep only)
- `quorum/CommitProcessor.java` comment lines up to ~150 (grep of comment lines)
- `SyncRequestProcessor.java` header comments (lines 1-134 via comment grep), lines 150-260
- `FinalRequestProcessor.java` lines 80-100
- `ZooKeeperServer.java` lines 514-543
- `ZKDatabase.java` lines 589-622 (plus grep for `clear();`)
- `persistence/TxnLog.java` lines 28-110
- `persistence/FileTxnLog.java` lines 50-110, 259-273, 369-378, 447-460
- `persistence/FileTxnSnapLog.java` lines 231-249, 305-357, 449-510
- `DataTree.java`, `persistence/FileSnap.java` (grep for "fuzzy" only)
- grep across main sources for `truncateLog(|.truncate(`, `updatingEpoch|UPDATING_EPOCH`
  (no match), and for the trace event names `SyncSelected|TxnDurable|BroadcastReady|ndjson`
  (no match anywhere in `source/`)

### Tests (`source/zookeeper-server/src/test/java/org/apache/zookeeper/`)
- `server/quorum/Zab1_0Test.java` grep of all tests/asserts; lines 136-230, 600-700, 750-800
- `server/quorum/QuorumPeerMainTest.java` grep of test names; lines 245-260, 335-350, 405-425, 1014-1045, 1150-1200
- `server/quorum/LearnerTest.java` grep; lines 262-370
- `test/TruncateTest.java` grep; lines 145-240
- `test/FollowerResyncConcurrencyTest.java` grep; lines 355-365, 555-615
- grep across tests for `AcceptedEpoch|CurrentEpoch|ACCEPTED_EPOCH|CURRENT_EPOCH` (file list),
  `older than the last zxid|is less than the current epoch|Unable to load database on disk` (no test match),
  `ZOOKEEPER-3104|ZOOKEEPER-1282|ZOOKEEPER-1291|testFollowerConversation`
- `server/quorum/EpochWriteFailureTest.java` was seen only as added in `hist.sh show 19d85670`; it was not cited.

## 3. Tools run on outputs
- `tla2sany.SANY` on `out/spec-annotated/{base,MC,Trace}.tla` (see `check.md`)
- `out/tmp/check_evidence.py` (my script, run with `python3 -I`), which checks block counts and
  quote locations (see `check.md`)
- `diff` between `spec-original/*` and `out/spec-annotated/*` (only `\* ` lines added)
