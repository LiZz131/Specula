/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file distributed
 * with this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.test.ClientBase.CONNECTION_TIMEOUT;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;
import java.io.IOException;
import java.net.SocketTimeoutException;
import java.util.Map;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicInteger;
import javax.security.sasl.SaslException;
import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.KeeperException;
import org.apache.zookeeper.PortAssignment;
import org.apache.zookeeper.ZooDefs.Ids;
import org.apache.zookeeper.ZooDefs.OpCode;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.data.Stat;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.server.quorum.Leader.Proposal;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.ClientBase.CountdownWatcher;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

/**
 * Specula update scenario U-LOSS (in-process re-election).  Same fault as the
 * update's DIFFSyncConsistencyTest (learners fail when reading UPTODATE, after
 * they ACKed NEWLEADER), but the surviving learners are NOT restarted from disk:
 * the old leader stops and they re-elect inside the same QuorumPeer processes.
 * A transaction that the old leader committed and served must stay visible.
 */
public class SpeculaReelectionAfterSyncFailureTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private final MainThread[] mt = new MainThread[SERVER_COUNT];

    @Test
    @Timeout(value = 180)
    public void testCommittedTxnVisibleAfterInProcessReelection() throws Exception {
        final int[] clientPorts = new int[SERVER_COUNT];
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < SERVER_COUNT; i++) {
            clientPorts[i] = PortAssignment.unique();
            sb.append("server." + i + "=127.0.0.1:" + PortAssignment.unique() + ":" + PortAssignment.unique()
                      + ":participant;127.0.0.1:" + clientPorts[i] + "\n");
        }
        String cfg = sb.toString();
        for (int i = 0; i < SERVER_COUNT; i++) {
            mt[i] = new MainThread(i, clientPorts[i], cfg, false) {
                @Override
                public TestQPMain getTestQPMain() {
                    return new MockTestQPMain();
                }
            };
            mt[i].start();
        }
        for (int i = 0; i < SERVER_COUNT; i++) {
            assertTrue(ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[i], CONNECTION_TIMEOUT));
        }
        int leader = findLeader();
        CountdownWatcher watch = new CountdownWatcher();
        ZooKeeper zk = new ZooKeeper("127.0.0.1:" + clientPorts[leader], CONNECTION_TIMEOUT, watch);
        watch.waitForConnected(CONNECTION_TIMEOUT);
        Map<Long, Proposal> outstanding = mt[leader].main.quorumPeer.leader.outstandingProposals;
        int previousTick = mt[leader].main.quorumPeer.tickTime;
        mt[leader].main.quorumPeer.tickTime = 10_000;
        Thread.sleep(previousTick);
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                mt[i].shutdown();
            }
        }
        try {
            zk.create("/zk" + leader, "zk".getBytes(), Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT);
            fail("create should not complete without a quorum");
        } catch (KeeperException e) {
            // expected: no quorum yet
        }
        Proposal p = null;
        for (Proposal q : outstanding.values()) {
            if (q.request.getHdr().getType() == OpCode.create) {
                p = q;
            }
        }
        assertNotNull(p, "leader has the create proposal");
        long deadline = System.currentTimeMillis() + 5000;
        while (!p.qvAcksetPairs.get(0).getAckset().contains((long) leader)) {
            assertTrue(System.currentTimeMillis() < deadline, "leader logged the proposal");
            Thread.sleep(50);
        }
        // Learners rejoin; each blocks when it reads UPTODATE (after ACKing NEWLEADER and
        // logging the DIFF proposals) until released, then fails once with a socket timeout.
        final CountDownLatch release = new CountDownLatch(1);
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i == leader) {
                continue;
            }
            mt[i].start();
            int c = 0;
            while (mt[i].getQuorumPeer() == null) {
                assertTrue(++c < 100, "follower started");
                Thread.sleep(100);
            }
            ((CustomQuorumPeer) mt[i].getQuorumPeer()).armOneShotUptodateFailure(release);
        }
        // The old leader establishes with their NEWLEADER ACKs and serves the txn.
        Stat seenAtOldLeader = null;
        for (int c = 0; c < 100 && seenAtOldLeader == null; c++) {
            try {
                seenAtOldLeader = zk.exists("/zk" + leader, false);
            } catch (KeeperException.ConnectionLossException e) {
                // retry
            }
            Thread.sleep(100);
        }
        assertNotNull(seenAtOldLeader, "old leader committed and served /zk" + leader);
        zk.close();
        // Old leader goes away; then the blocked learners time out (one shot) and
        // re-elect inside the same QuorumPeer processes.
        mt[leader].shutdown();
        release.countDown();
        int newLeader = -1;
        deadline = System.currentTimeMillis() + 60_000;
        while (newLeader < 0 && System.currentTimeMillis() < deadline) {
            for (int i = 0; i < SERVER_COUNT; i++) {
                if (i != leader && mt[i].getQuorumPeer() != null
                    && mt[i].getQuorumPeer().leader != null
                    && mt[i].getQuorumPeer().getZabState() == QuorumPeer.ZabState.BROADCAST) {
                    newLeader = i;
                }
            }
            Thread.sleep(100);
        }
        assertTrue(newLeader >= 0, "surviving learners elected a new leader");
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i == leader) {
                continue;
            }
            assertTrue(ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[i], CONNECTION_TIMEOUT),
                "server " + i + " serving");
            ZooKeeper z = new ZooKeeper("127.0.0.1:" + clientPorts[i], CONNECTION_TIMEOUT, watch);
            try {
                long d = System.currentTimeMillis() + CONNECTION_TIMEOUT;
                Stat st = null;
                boolean answered = false;
                while (!answered && System.currentTimeMillis() < d) {
                    try {
                        st = z.exists("/zk" + leader, false);
                        answered = true;
                    } catch (KeeperException.ConnectionLossException e) {
                        Thread.sleep(100);
                    }
                }
                LOG.info("SPECULA server {} (new leader {}) exists(/zk{}) = {}", i, newLeader, leader, st);
                assertNotNull(st, "Committed /zk" + leader + " (served by the old leader) is missing at server "
                    + i + " after in-process re-election (new leader " + newLeader + ")");
            } finally {
                z.close();
            }
        }
    }

    @AfterEach
    public void tearDown() throws InterruptedException {
        for (MainThread m : mt) {
            if (m != null) {
                m.shutdown();
            }
        }
    }

    private int findLeader() {
        for (int i = 0; i < mt.length; i++) {
            if (mt[i].main.quorumPeer.leader != null) {
                return i;
            }
        }
        return -1;
    }

    static class CustomQuorumPeer extends QuorumPeer {
        private final AtomicInteger shots = new AtomicInteger(0);
        private volatile CountDownLatch gate;

        CustomQuorumPeer() throws SaslException {
        }

        @Override
        protected Follower makeFollower(FileTxnSnapLog logFactory) throws IOException {
            return new Follower(this, new FollowerZooKeeperServer(logFactory, this, this.getZkDb())) {
                @Override
                void readPacket(QuorumPacket pp) throws IOException {
                    super.readPacket(pp);
                    if (pp.getType() == Leader.UPTODATE && shots.getAndUpdate(v -> v > 0 ? v - 1 : 0) > 0) {
                        try {
                            gate.await(60, TimeUnit.SECONDS);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                        throw new SocketTimeoutException("Specula injected timeout reading "
                            + LearnerHandler.packetToString(pp));
                    }
                }
            };
        }

        void armOneShotUptodateFailure(CountDownLatch gate) {
            this.gate = gate;
            this.shots.set(1);
        }
    }

    static class MockTestQPMain extends TestQPMain {
        @Override
        protected QuorumPeer getQuorumPeer() throws SaslException {
            return new CustomQuorumPeer();
        }
    }
}
