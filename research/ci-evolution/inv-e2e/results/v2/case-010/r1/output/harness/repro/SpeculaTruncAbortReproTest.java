/*
 * Licensed to the Apache Software Foundation (ASF) under one or more
 * contributor license agreements. See the NOTICE file distributed with
 * this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0.
 */
package org.apache.zookeeper.server.quorum;

import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import java.io.IOException;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;
import javax.security.sasl.SaslException;
import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.PortAssignment;
import org.apache.zookeeper.ZooDefs.Ids;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.ZooKeeper.States;
import org.apache.zookeeper.common.X509Exception;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.test.ClientBase;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Specula case-010 code observation for MC-1 (model counterexample
 * spec/output/mc/smoke2-focused-txn1.log): a learner whose TRUNC sync applied a
 * COMMIT directly in memory (writeToTxnLog == false) and then failed before
 * the NEWLEADER snapshot keeps that in-memory database, because
 * Learner.shutdown only forces a full shutdown for SyncMode.SNAP.
 *
 * Fault/timing control uses the same hook points as the update's own
 * testDiffSyncAfterSnap (follower readPacket NEWLEADER hook) plus the follower
 * writePacket and leader startForwarding hooks that QuorumPeerMainTest already
 * overrides.  Oracle: the update's own oracle -- after a restart from disk the
 * follower must still have every committed node.
 */
public class SpeculaTruncAbortReproTest extends QuorumPeerTestBase {

    private static final Logger LOG = LoggerFactory.getLogger(SpeculaTruncAbortReproTest.class);

    static class Hooks {
        final AtomicBoolean dropOnNextAck = new AtomicBoolean(false);   // follower A
        final AtomicBoolean holdNextAck = new AtomicBoolean(false);     // follower B
        volatile CountDownLatch ackGate = new CountDownLatch(1);         // follower B
        final AtomicBoolean abortOnNewLeader = new AtomicBoolean(false); // follower A
        final AtomicBoolean commitInStartForwarding = new AtomicBoolean(false); // leader
        final AtomicLong droppedAckZxid = new AtomicLong(-1);
        final AtomicLong committedAtStartForwarding = new AtomicLong(-1);
        final AtomicBoolean newLeaderAborted = new AtomicBoolean(false);
        volatile Hooks peerB;
        volatile Hooks peerA;
    }

    static class HookedPeer extends QuorumPeer {

        final Hooks hooks;

        HookedPeer(Hooks hooks) throws SaslException {
            this.hooks = hooks;
        }

        @Override
        protected Follower makeFollower(FileTxnSnapLog logFactory) throws IOException {
            return new Follower(this, new FollowerZooKeeperServer(logFactory, this, this.getZkDb())) {
                @Override
                void writePacket(QuorumPacket pp, boolean flush) throws IOException {
                    if (pp != null && pp.getType() == Leader.ACK && (pp.getZxid() & 0xffffffffL) != 0) {
                        if (hooks.dropOnNextAck.compareAndSet(true, false)) {
                            hooks.droppedAckZxid.set(pp.getZxid());
                            LOG.info("SPECULA-REPRO follower {} logged 0x{} and drops the leader connection instead of ACK",
                                     self.getId(), Long.toHexString(pp.getZxid()));
                            throw new IOException("specula: connection lost before ACK");
                        }
                        if (hooks.holdNextAck.compareAndSet(true, false)) {
                            LOG.info("SPECULA-REPRO follower {} holds ACK 0x{}", self.getId(), Long.toHexString(pp.getZxid()));
                            try {
                                hooks.ackGate.await(60, TimeUnit.SECONDS);
                            } catch (InterruptedException e) {
                                Thread.currentThread().interrupt();
                            }
                        }
                    }
                    super.writePacket(pp, flush);
                }

                @Override
                void readPacket(QuorumPacket qp) throws IOException {
                    super.readPacket(qp);
                    if (qp.getType() == Leader.NEWLEADER && hooks.abortOnNewLeader.compareAndSet(true, false)) {
                        hooks.newLeaderAborted.set(true);
                        LOG.info("SPECULA-REPRO follower {} fails its sync at NEWLEADER, syncMode={}",
                                 self.getId(), self.getSyncMode());
                        throw new IOException("specula: read timed out at NEWLEADER");
                    }
                }
            };
        }

        @Override
        protected Leader makeLeader(FileTxnSnapLog logFactory) throws IOException, X509Exception {
            return new Leader(this, new LeaderZooKeeperServer(logFactory, this, this.getZkDb())) {
                @Override
                public long startForwarding(LearnerHandler handler, long lastSeenZxid) {
                    if (hooks.commitInStartForwarding.compareAndSet(true, false)) {
                        // The TRUNC/DIFF/SNAP decision has been made for this learner; let the
                        // held ACK through so the proposal commits before this handler is
                        // registered (it is then forwarded from toBeApplied).
                        long target = hooks.peerA.droppedAckZxid.get();
                        hooks.peerB.ackGate.countDown();
                        long deadline = System.currentTimeMillis() + 30000;
                        while (lastCommitted < target && System.currentTimeMillis() < deadline) {
                            try {
                                Thread.sleep(5);
                            } catch (InterruptedException e) {
                                Thread.currentThread().interrupt();
                                break;
                            }
                        }
                        hooks.committedAtStartForwarding.set(lastCommitted);
                        LOG.info("SPECULA-REPRO leader startForwarding(sid={}, lastSeen=0x{}) lastCommitted=0x{} target=0x{}",
                                 handler.getSid(), Long.toHexString(lastSeenZxid),
                                 Long.toHexString(lastCommitted), Long.toHexString(target));
                    }
                    return super.startForwarding(handler, lastSeenZxid);
                }
            };
        }
    }

    @Test
    public void testTruncSyncAbortKeepsUnloggedCommit() throws Exception {
        final int n = 3;
        MainThread[] mt = new MainThread[n];
        ZooKeeper[] zk = new ZooKeeper[n];
        Hooks[] hooks = new Hooks[n];
        try {
            int[] clientPorts = new int[n];
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < n; i++) {
                clientPorts[i] = PortAssignment.unique();
                sb.append("server." + i + "=127.0.0.1:" + PortAssignment.unique() + ":" + PortAssignment.unique()
                          + ":participant;127.0.0.1:" + clientPorts[i] + "\n");
            }
            String cfg = sb.toString();
            for (int i = 0; i < n; i++) {
                final Hooks h = new Hooks();
                hooks[i] = h;
                mt[i] = new MainThread(i, clientPorts[i], cfg, false) {
                    @Override
                    public TestQPMain getTestQPMain() {
                        return new TestQPMain() {
                            @Override
                            protected QuorumPeer getQuorumPeer() throws SaslException {
                                return new HookedPeer(h);
                            }
                        };
                    }
                };
                mt[i].start();
                zk[i] = new ZooKeeper("127.0.0.1:" + clientPorts[i], ClientBase.CONNECTION_TIMEOUT, this);
            }
            waitForAll(zk, States.CONNECTED);

            int leader = -1;
            int a = -1;
            int b = -1;
            for (int i = 0; i < n; i++) {
                if (mt[i].main.quorumPeer.leader != null) {
                    leader = i;
                } else if (a == -1) {
                    a = i;
                } else {
                    b = i;
                }
            }
            assertTrue(leader >= 0 && a >= 0 && b >= 0, "need a leader and two followers");
            hooks[leader].peerA = hooks[a];
            hooks[leader].peerB = hooks[b];

            // Arm: B holds its ACK, A logs then loses the connection instead of ACKing,
            // the leader commits inside A's next startForwarding, A fails at NEWLEADER once.
            hooks[b].holdNextAck.set(true);
            hooks[a].dropOnNextAck.set(true);
            hooks[leader].commitInStartForwarding.set(true);
            hooks[a].abortOnNewLeader.set(true);

            final CountDownLatch created = new CountDownLatch(1);
            zk[leader].create("/specula-trunc-1", new byte[1], Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT,
                              (rc, path, ctx, name) -> created.countDown(), null);
            assertTrue(created.await(60, TimeUnit.SECONDS), "first create must commit");

            // A rejoins after the aborted TRUNC session (now with the reused in-memory DB).
            long deadline = System.currentTimeMillis() + 60000;
            while (!hooks[a].newLeaderAborted.get() && System.currentTimeMillis() < deadline) {
                Thread.sleep(50);
            }
            LOG.info("SPECULA-REPRO path: droppedAck=0x{} committedAtStartForwarding=0x{} newLeaderAborted={}",
                     Long.toHexString(hooks[a].droppedAckZxid.get()),
                     Long.toHexString(hooks[leader].committedAtStartForwarding.get()),
                     hooks[a].newLeaderAborted.get());
            waitForOne(zk[a], States.CONNECTED);
            Thread.sleep(1000);
            boolean inMemoryBefore = zk[a].exists("/specula-trunc-1", false) != null;

            zk[leader].create("/specula-trunc-2", new byte[1], Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT);
            Thread.sleep(1000);

            mt[a].shutdown();
            waitForOne(zk[a], States.CONNECTING);
            mt[a].start();
            waitForOne(zk[a], States.CONNECTED);
            Thread.sleep(1000);
            boolean afterRestart1 = zk[a].exists("/specula-trunc-1", false) != null;
            boolean afterRestart2 = zk[a].exists("/specula-trunc-2", false) != null;
            boolean onLeader1 = zk[leader].exists("/specula-trunc-1", false) != null;
            LOG.info("SPECULA-REPRO RESULT inMemoryBeforeRestart={} node1AfterRestart={} node2AfterRestart={} node1OnLeader={}",
                     inMemoryBefore, afterRestart1, afterRestart2, onLeader1);
            assertTrue(hooks[a].newLeaderAborted.get(), "precondition: A failed its sync at NEWLEADER");
            assertTrue(hooks[leader].committedAtStartForwarding.get() >= hooks[a].droppedAckZxid.get(),
                       "precondition: the proposal committed inside A's startForwarding");
            assertTrue(onLeader1, "the first node is committed on the leader");
            assertNotNull(zk[a].exists("/specula-trunc-1", false),
                          "committed node must survive the follower's restart from disk");
        } finally {
            for (int i = 0; i < n; i++) {
                if (hooks[i] != null) {
                    hooks[i].ackGate.countDown();
                }
                if (mt[i] != null) {
                    mt[i].shutdown();
                }
                if (zk[i] != null) {
                    zk[i].close();
                }
            }
        }
    }
}
