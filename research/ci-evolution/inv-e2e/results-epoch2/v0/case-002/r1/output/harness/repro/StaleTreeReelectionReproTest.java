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
 * Specula reproduction for model counterexample MC-2 (scenario U-2).
 *
 * Same setup as DIFFSyncConsistencyTest (the old leader holds an uncommitted
 * txn in its log; followers DIFF-sync it, ACK NEWLEADER and fail when reading
 * UPTODATE).  Difference: the followers are NOT restarted.  Only the old
 * leader is stopped (a partition/crash of one server), and the two followers
 * re-elect in-process.  The test then reads the txn from the new leader.
 */
public class StaleTreeReelectionReproTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private final MainThread[] mt = new MainThread[SERVER_COUNT];

    @Test
    @Timeout(value = 180)
    public void inProcessReelectionAfterUptodateFailure() throws Exception {
        final int leaderTimeoutMs = 10_000;
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
                    return new ReproQPMain();
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
        mt[leader].main.quorumPeer.tickTime = leaderTimeoutMs;
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
        assertNotNull(p, "old leader has no create proposal");
        int waited = 0;
        while (!p.qvAcksetPairs.get(0).getAckset().contains((long) leader)) {
            if (waited > 2000) {
                fail("create not synced on the old leader");
            }
            Thread.sleep(100);
            waited += 100;
        }

        // Followers DIFF-sync the txn, ACK NEWLEADER, then fail at UPTODATE.
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i == leader) {
                continue;
            }
            mt[i].start();
            int c = 0;
            while (mt[i].getQuorumPeer() == null) {
                if (++c > 100) {
                    fail("cannot start follower " + i);
                }
                Thread.sleep(100);
            }
            ((ReproQuorumPeer) mt[i].getQuorumPeer()).setInjectError(true);
        }
        boolean visibleAtOldLeader = false;
        for (int c = 0; c < 100 && !visibleAtOldLeader; c++) {
            try {
                visibleAtOldLeader = zk.exists("/zk" + leader, false) != null;
            } catch (KeeperException.ConnectionLossException e) {
                // retry
            }
            Thread.sleep(100);
        }
        assertTrue(visibleAtOldLeader, "old leader never served the txn after the NEWLEADER quorum");
        LOG.info("REPRO: /zk{} visible at old leader {} (epoch {})", leader, leader,
                 mt[leader].main.quorumPeer.getCurrentEpoch());

        // Stop only the old leader; the followers stay in-process.
        mt[leader].shutdown();
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                ((ReproQuorumPeer) mt[i].getQuorumPeer()).setInjectError(false);
                LOG.info("REPRO: follower {} lastLoggedZxid=0x{} (DataTree) after old-leader stop", i,
                         Long.toHexString(mt[i].getQuorumPeer().getLastLoggedZxid()));
            }
        }
        zk.close();

        int newLeader = -1;
        for (int c = 0; c < 600 && newLeader < 0; c++) {
            for (int i = 0; i < SERVER_COUNT; i++) {
                if (i != leader && mt[i].getQuorumPeer() != null
                    && mt[i].getQuorumPeer().leader != null
                    && mt[i].getQuorumPeer().getPeerState() == QuorumPeer.ServerState.LEADING
                    && mt[i].getQuorumPeer().getActiveServer() != null
                    && mt[i].getQuorumPeer().getActiveServer().isRunning()) {
                    newLeader = i;
                }
            }
            Thread.sleep(100);
        }
        assertTrue(newLeader >= 0, "no in-process re-election among the followers");
        assertTrue(ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[newLeader], CONNECTION_TIMEOUT));
        CountdownWatcher watch2 = new CountdownWatcher();
        ZooKeeper zk2 = new ZooKeeper("127.0.0.1:" + clientPorts[newLeader], CONNECTION_TIMEOUT, watch2);
        watch2.waitForConnected(CONNECTION_TIMEOUT);
        Stat st = null;
        for (int c = 0; c < 50; c++) {
            try {
                st = zk2.exists("/zk" + leader, false);
                break;
            } catch (KeeperException.ConnectionLossException e) {
                Thread.sleep(100);
            }
        }
        LOG.info("REPRO RESULT: new leader {} (epoch {}, lastLoggedZxid=0x{}) sees /zk{}: {}", newLeader,
                 mt[newLeader].getQuorumPeer().getCurrentEpoch(),
                 Long.toHexString(mt[newLeader].getQuorumPeer().getLastLoggedZxid()), leader, st != null);
        zk2.close();
        assertNotNull(st, "Data inconsistency: /zk" + leader + " was served by the old leader after its NEWLEADER "
                          + "quorum but the in-process re-elected leader " + newLeader + " does not have it");
    }

    @AfterEach
    public void tearDown() {
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

    static class ReproQuorumPeer extends QuorumPeer {
        private volatile boolean injectError = false;

        ReproQuorumPeer() throws SaslException {
        }

        @Override
        protected Follower makeFollower(FileTxnSnapLog logFactory) throws IOException {
            return new Follower(this, new FollowerZooKeeperServer(logFactory, this, this.getZkDb())) {
                @Override
                void readPacket(QuorumPacket pp) throws IOException {
                    super.readPacket(pp);
                    if (injectError && pp.getType() == Leader.UPTODATE) {
                        throw new SocketTimeoutException("injected timeout reading UPTODATE");
                    }
                }
            };
        }

        void setInjectError(boolean injectError) {
            this.injectError = injectError;
        }
    }

    static class ReproQPMain extends TestQPMain {
        @Override
        protected QuorumPeer getQuorumPeer() throws SaslException {
            return new ReproQuorumPeer();
        }
    }
}
