"""Add the case-010 incremental probes on top of the rebased V0 instrumentation.

Usage: python3 -I apply_update_probes.py <artifact-root> [old|new]

The V0 patch (patches/instrumentation-v0.patch) must already be applied.  Every
edit is an exact-anchor replacement; a missing anchor aborts without writing.
The 'old' variant targets the exact-old Learner.shutdown (zk.shutdown()) so the
same probes can observe the old implementation as a control.
"""
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
variant = sys.argv[2] if len(sys.argv) > 2 else "new"
base = root / "zookeeper-server/src/main/java/org/apache/zookeeper/server"
edits = []


def edit(rel, old, new, count=1):
    edits.append((base / rel, old, new, count))


# ---------------------------------------------------------------- SpeculaTrace
edit("quorum/SpeculaTrace.java",
     """    public static void recovery(QuorumPeer self) {
        emit(self, "RestartLoadDatabase", "{}");
    }
""",
     """    private static boolean dbInit(QuorumPeer self) {
        return self.getZkDb() != null && self.getZkDb().isInitialized();
    }

    /** Process start: QuorumPeer.start -> loadDataBase. */
    public static void recovery(QuorumPeer self) {
        emit(self, "RestartLoadDatabase", "{\\"dbInitialized\\":" + dbInit(self) + "}");
    }

    /** In-process reload: QuorumPeer.getLastLoggedZxid with an uninitialized db. */
    public static void reload(QuorumPeer self) {
        emit(self, "ReloadDatabase", "{\\"dbInitialized\\":" + dbInit(self) + "}");
    }

    /** Learner.shutdown after zk.shutdown(...) returned. */
    public static void learnerShutdown(QuorumPeer self, boolean fully, boolean zkRunning,
                                       boolean syncAlive) {
        emit(self, "LearnerShutdown",
             "{\\"fully\\":" + fully + ",\\"zkRunning\\":" + zkRunning
             + ",\\"syncAlive\\":" + syncAlive
             + ",\\"dbInitialized\\":" + dbInit(self) + "}");
    }

    /** Learner.syncWithLeader after the DIFF/SNAP/TRUNC branch completed. */
    public static void receiveSyncMode(QuorumPeer self) {
        emit(self, "ReceiveSyncMode",
             "{\\"mode\\":\\"" + self.getSyncMode() + "\\",\\"dbInitialized\\":" + dbInit(self) + "}");
    }

    /** Learner.syncWithLeader: COMMIT applied directly in memory (!writeToTxnLog). */
    public static void syncApply(QuorumPeer self, org.apache.zookeeper.txn.TxnHeader hdr) {
        if (hdr == null) {
            return;
        }
        int type = hdr.getType();
        if (!(type == OpCode.create || type == OpCode.create2
              || type == OpCode.delete || type == OpCode.setData)) {
            return;
        }
        synchronized (LOCK) {
            int id = tx(hdr.getZxid());
            emit(self, "SyncApplyCommitted", "{\\"tx\\":" + id + "}");
        }
    }

    /** SyncRequestProcessor.flush: stale when the processor's server is not active. */
    public static void flush(ZooKeeperServer zks, Request request) {
        if (!isModeled(request) || !(zks instanceof QuorumZooKeeperServer)) {
            return;
        }
        QuorumPeer self = ((QuorumZooKeeperServer) zks).self;
        Leader leader = self.leader;
        Follower follower = self.follower;
        Observer observer = self.observer;
        boolean active = (leader != null && leader.zk == zks)
                         || (follower != null && follower.zk == zks)
                         || (observer != null && observer.zk == zks);
        synchronized (LOCK) {
            int id = tx(request.zxid);
            emit(self, "FlushTxnLog", "{\\"tx\\":" + id + ",\\"stale\\":" + !active + "}");
        }
    }
""")


edit("quorum/SpeculaTrace.java",
     """    /** Process start: QuorumPeer.start -> loadDataBase. */""",
     """    private static int txAtMost(long zxid) {
        int best = 0;
        for (Map.Entry<Long, Integer> e : TX_IDS.entrySet()) {
            if (e.getKey() <= zxid && e.getValue() > best) {
                best = e.getValue();
            }
        }
        return best;
    }

    /** LearnerHandler.syncFollower after startForwarding (committed-log read lock held). */
    public static void syncDecision(QuorumPeer leaderSelf, long learnerSid, String mode,
                                    long maxCommittedLog, long lastCommitted) {
        synchronized (LOCK) {
            emit(leaderSelf, "LeaderSyncDecision",
                 "{\\"learner\\":\\"" + node(learnerSid) + "\\",\\"mode\\":\\"" + mode
                 + "\\",\\"maxCommittedTx\\":" + txAtMost(maxCommittedLog)
                 + ",\\"committedTx\\":" + txAtMost(lastCommitted) + "}");
        }
    }

    /** Process start: QuorumPeer.start -> loadDataBase. */""")
edit("quorum/LearnerHandler.java",
     """            leaderLastZxid = learnerMaster.startForwarding(this, currentZxid);
""",
     """            leaderLastZxid = learnerMaster.startForwarding(this, currentZxid);
            if (learnerMaster instanceof Leader) {
                QuorumPacket speculaFirst = queuedPackets.peek();
                String speculaMode = needSnap ? "SNAP"
                    : (speculaFirst != null && speculaFirst.getType() == Leader.TRUNC ? "TRUNC" : "DIFF");
                Leader speculaLeader = (Leader) learnerMaster;
                SpeculaTrace.syncDecision(speculaLeader.self, getSid(), speculaMode,
                                          maxCommittedLog, speculaLeader.lastCommitted);
            }
""")

# ------------------------------------------------------------------ QuorumPeer
edit("quorum/QuorumPeer.java",
     """            }
            SpeculaTrace.recovery(this);
        } catch (IOException ie) {""",
     """            }
        } catch (IOException ie) {""")
edit("quorum/QuorumPeer.java",
     """        loadDataBase();
        startServerCnxnFactory();""",
     """        loadDataBase();
        SpeculaTrace.recovery(this);
        startServerCnxnFactory();""")
edit("quorum/QuorumPeer.java",
     """    public long getLastLoggedZxid() {
        if (!zkDb.isInitialized()) {
            loadDataBase();
        }""",
     """    public long getLastLoggedZxid() {
        if (!zkDb.isInitialized()) {
            loadDataBase();
            SpeculaTrace.reload(this);
        }""")

# --------------------------------------------------------- SyncRequestProcessor
edit("SyncRequestProcessor.java",
     """            SpeculaTrace.txn("FlushTxnLog", zks, request);""",
     """            SpeculaTrace.flush(zks, request);""")

# --------------------------------------------------------------------- Learner
edit("quorum/Learner.java",
     """            zk.getZKDatabase().initConfigInZKDatabase(self.getQuorumVerifier());
            zk.createSessionTracker();

            long lastQueued = 0;""",
     """            SpeculaTrace.receiveSyncMode(self);
            zk.getZKDatabase().initConfigInZKDatabase(self.getQuorumVerifier());
            zk.createSessionTracker();

            long lastQueued = 0;""")
edit("quorum/Learner.java",
     """                        } else {
                            zk.processTxn(pif.hdr, pif.rec);
                            packetsNotCommitted.remove();
                        }""",
     """                        } else {
                            zk.processTxn(pif.hdr, pif.rec);
                            SpeculaTrace.syncApply(self, pif.hdr);
                            packetsNotCommitted.remove();
                        }""")
if variant == "new":
    edit("quorum/Learner.java",
         """            zk.shutdown(self.getSyncMode().equals(QuorumPeer.SyncMode.SNAP));
        }""",
         """            boolean speculaFully = self.getSyncMode().equals(QuorumPeer.SyncMode.SNAP);
            boolean speculaRunning = zk.isRunning();
            zk.shutdown(speculaFully);
            SpeculaTrace.learnerShutdown(self, speculaFully, speculaRunning,
                zk.syncProcessor != null && zk.syncProcessor.isAlive());
        }""")
else:
    edit("quorum/Learner.java",
         """        if (zk != null) {
            zk.shutdown();
        }""",
         """        if (zk != null) {
            boolean speculaRunning = zk.isRunning();
            zk.shutdown();
            SpeculaTrace.learnerShutdown(self, false, speculaRunning,
                zk.syncProcessor != null && zk.syncProcessor.isAlive());
        }""")


# ------------------------------------------------- update-focused test scenario
test_base = root / "zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum"
edits.append((test_base / "SpeculaTraceScenarioTest.java",
     """        servers.shutDownAllServers();
        waitForAll(servers.zk, States.CONNECTING);
    }
}""",
     """        servers.shutDownAllServers();
        waitForAll(servers.zk, States.CONNECTING);
    }

    /**
     * Update-focused (case-010): a lagging follower is forced to SNAP-sync
     * (LearnerHandler.FORCE_SNAP_SYNC, the mechanism used by the update's
     * testDiffSyncAfterSnap) and the sync completes, so the NEWLEADER snapshot
     * persists the in-memory image; a later proposal is logged on top of it.
     */
    @Test
    public void testForcedSnapSyncCompletes() throws Exception {
        numServers = 3;
        servers = LaunchServers(numServers, 500);
        try {
            int leader = servers.findLeader();
            assertTrue(leader >= 0, "the initial election must choose a leader");
            int follower = servers.findAnyFollower();
            assertTrue(follower >= 0, "the ensemble must have a follower");
            servers.mt[follower].shutdown();
            waitForOne(servers.zk[follower], States.CONNECTING);

            byte[] missed = new byte[]{7};
            servers.zk[leader].create("/specula-snap", missed, Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT);

            System.setProperty(LearnerHandler.FORCE_SNAP_SYNC, "true");
            servers.mt[follower].start();
            servers.restartClient(follower, this);
            waitForOne(servers.zk[follower], States.CONNECTED);
            System.clearProperty(LearnerHandler.FORCE_SNAP_SYNC);
            assertArrayEquals(missed, servers.zk[follower].getData("/specula-snap", false, null));

            byte[] after = new byte[]{8};
            servers.zk[leader].setData("/specula-snap", after, -1);
            Thread.sleep(500);
            assertArrayEquals(after, servers.zk[follower].getData("/specula-snap", false, null));
        } finally {
            System.clearProperty(LearnerHandler.FORCE_SNAP_SYNC);
        }
        servers.shutDownAllServers();
        waitForAll(servers.zk, States.CONNECTING);
    }
}""", 1))

# Validate every anchor before writing anything.
contents = {}
for path, old, new, count in edits:
    text = contents.get(path)
    if text is None:
        text = path.read_text()
    if text.count(old) != count:
        sys.exit(f"anchor count {text.count(old)} != {count} in {path}:\n{old}")
    contents[path] = text.replace(old, new, count)
for path, text in contents.items():
    path.write_text(text)
print(f"applied {len(edits)} incremental probe edits ({variant})")
