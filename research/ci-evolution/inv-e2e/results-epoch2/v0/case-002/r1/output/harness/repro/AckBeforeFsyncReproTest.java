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
import java.util.Map;
import javax.security.sasl.SaslException;
import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.KeeperException;
import org.apache.zookeeper.PortAssignment;
import org.apache.zookeeper.ZooDefs.Ids;
import org.apache.zookeeper.ZooDefs.OpCode;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.data.Stat;
import org.apache.zookeeper.server.Request;
import org.apache.zookeeper.server.ZKDatabase;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.server.quorum.Leader.Proposal;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.ClientBase.CountdownWatcher;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

/**
 * Specula reproduction for model counterexample MC-1 (scenario U-1): does a
 * NEWLEADER-ACK quorum imply that the acknowledging learners hold the synced
 * txn durably?
 *
 * Fault injection (followers only): appends to the txn log stall (slow disk);
 * a "crash" makes a stalled append fail without writing, then the follower
 * process is restarted from disk.  Control logic: if the old leader serves
 * the txn while the followers' appends are stalled, a crash at that moment
 * must not lose it (Zab: the NEWLEADER ACK attests the history).  If the
 * leader does not serve within the window (an implementation that waits for
 * durability before ACKing), the stall is released first and the test
 * continues normally.
 */
public class AckBeforeFsyncReproTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private final MainThread[] mt = new MainThread[SERVER_COUNT];
    static volatile boolean stall = false;
    static volatile boolean crash = false;
    static final Object LOCK = new Object();

    static class StallingZKDatabase extends ZKDatabase {
        StallingZKDatabase(FileTxnSnapLog snapLog) {
            super(snapLog);
        }

        @Override
        public boolean append(Request si) throws IOException {
            synchronized (LOCK) {
                while (stall && !crash) {
                    try {
                        LOCK.wait(50);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                        throw new IOException("interrupted while stalled");
                    }
                }
            }
            if (crash) {
                throw new IOException("injected crash before the txn reached the log");
            }
            return super.append(si);
        }
    }

    static class StallingQuorumPeer extends QuorumPeer {
        volatile boolean faulty = false;

        StallingQuorumPeer() throws SaslException {
        }

        @Override
        public void setZKDatabase(ZKDatabase database) {
            super.setZKDatabase(new StallingZKDatabase(getTxnFactory()));
        }
    }

    static class StallingQPMain extends TestQPMain {
        @Override
        protected QuorumPeer getQuorumPeer() throws SaslException {
            return new StallingQuorumPeer();
        }
    }

    @Test
    @Timeout(value = 240)
    public void newLeaderAckQuorumSurvivesLearnerCrash() throws Exception {
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
                    return new StallingQPMain();
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
            fail("create should fail without quorum");
        } catch (KeeperException e) {
            // expected
        }
        Proposal p = null;
        for (Proposal q : outstanding.values()) {
            if (q.request.getHdr().getType() == OpCode.create) {
                p = q;
            }
        }
        assertNotNull(p);
        int waited = 0;
        while (!p.qvAcksetPairs.get(0).getAckset().contains((long) leader)) {
            if (waited > 2000) {
                fail("create not synced on the old leader");
            }
            Thread.sleep(100);
            waited += 100;
        }
        // Old leader's own log already holds the txn; from now on follower appends stall.
        stall = true;
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                mt[i].start();
            }
        }
        boolean servedWhileStalled = false;
        for (int c = 0; c < 150 && !servedWhileStalled; c++) {
            try {
                servedWhileStalled = zk.exists("/zk" + leader, false) != null;
            } catch (KeeperException.ConnectionLossException e) {
                // retry
            }
            Thread.sleep(100);
        }
        LOG.info("REPRO: old leader {} served /zk{} while follower log appends were stalled: {}",
                 leader, leader, servedWhileStalled);
        if (servedWhileStalled) {
            // Crash the followers before their stalled appends reach the log.
            crash = true;
            synchronized (LOCK) {
                LOCK.notifyAll();
            }
        } else {
            // Implementation waits for durability before ACK: release the disk.
            stall = false;
            synchronized (LOCK) {
                LOCK.notifyAll();
            }
            for (int c = 0; c < 300; c++) {
                try {
                    if (zk.exists("/zk" + leader, false) != null) {
                        break;
                    }
                } catch (KeeperException.ConnectionLossException e) {
                    // retry
                }
                Thread.sleep(100);
            }
            crash = true;
        }
        Thread.sleep(500);
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                mt[i].shutdown();
            }
        }
        zk.close();
        mt[leader].shutdown();       // old leader partitioned/stopped
        stall = false;
        crash = false;
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                mt[i].start();       // process restart from disk
            }
        }
        int newLeader = -1;
        for (int c = 0; c < 600 && newLeader < 0; c++) {
            for (int i = 0; i < SERVER_COUNT; i++) {
                if (i != leader && mt[i].getQuorumPeer() != null && mt[i].main.quorumPeer != null
                    && mt[i].main.quorumPeer.leader != null
                    && mt[i].getQuorumPeer().getActiveServer() != null
                    && mt[i].getQuorumPeer().getActiveServer().isRunning()) {
                    newLeader = i;
                }
            }
            Thread.sleep(100);
        }
        assertTrue(newLeader >= 0, "no new leader among the restarted followers");
        assertTrue(ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[newLeader], CONNECTION_TIMEOUT));
        CountdownWatcher w2 = new CountdownWatcher();
        ZooKeeper zk2 = new ZooKeeper("127.0.0.1:" + clientPorts[newLeader], CONNECTION_TIMEOUT, w2);
        w2.waitForConnected(CONNECTION_TIMEOUT);
        Stat st = null;
        for (int c = 0; c < 50; c++) {
            try {
                st = zk2.exists("/zk" + leader, false);
                break;
            } catch (KeeperException.ConnectionLossException e) {
                Thread.sleep(100);
            }
        }
        LOG.info("REPRO RESULT: servedWhileStalled={} new leader {} (epoch {}) sees /zk{}: {}", servedWhileStalled,
                 newLeader, mt[newLeader].getQuorumPeer().getCurrentEpoch(), leader, st != null);
        zk2.close();
        assertNotNull(st, "Data loss: /zk" + leader + " was served after the NEWLEADER-ACK quorum but is missing at "
                          + "the new leader after the acknowledging followers crashed before their log write");
    }

    @AfterEach
    public void tearDown() {
        stall = false;
        crash = false;
        for (MainThread t : mt) {
            try {
                if (t != null) {
                    t.shutdown();
                }
            } catch (InterruptedException e) {
                LOG.warn("interrupted", e);
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
}
