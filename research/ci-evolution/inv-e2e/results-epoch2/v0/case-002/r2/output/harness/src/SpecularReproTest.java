/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file
 * distributed with this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.test.ClientBase.CONNECTION_TIMEOUT;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;
import java.io.IOException;
import java.net.SocketTimeoutException;
import java.util.Map;
import java.util.concurrent.ConcurrentLinkedQueue;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;
import javax.security.sasl.SaslException;
import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.KeeperException;
import org.apache.zookeeper.PortAssignment;
import org.apache.zookeeper.ZooDefs.Ids;
import org.apache.zookeeper.ZooDefs.OpCode;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.ZooKeeper.States;
import org.apache.zookeeper.data.Stat;
import org.apache.zookeeper.server.FinalRequestProcessor;
import org.apache.zookeeper.server.Request;
import org.apache.zookeeper.server.RequestProcessor;
import org.apache.zookeeper.server.SyncRequestProcessor;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.server.quorum.Leader.Proposal;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.ClientBase.CountdownWatcher;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

/**
 * Specular reproduction tests for the update to Learner.syncWithLeader.
 * Real three-peer ensembles in one JVM (QuorumPeerTestBase), with timing
 * assistance and crash emulation at real code boundaries:
 *  - delayed SyncThread start (no logic change): the requests enqueued by
 *    FollowerZooKeeperServer.logRequest stay in memory when the NEWLEADER ACK
 *    is sent; a follower "crash" discards that thread with the process;
 *  - scheduling delay: an armed follower's learner thread is delayed right
 *    before writing its NEWLEADER ACK (GC pause / preemption).
 * The setup phase (leader logs a transaction while both followers are down,
 * then is re-elected in a new epoch and DIFF-syncs it) is the one used by the
 * update's own DIFFSyncConsistencyTest.
 */
public class SpecularReproTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private final MainThread[] mt = new MainThread[SERVER_COUNT];

    /** SyncThread start is delayed while SYNC_DELAY_ARMED (timing assistance). */
    static final AtomicBoolean SYNC_DELAY_ARMED = new AtomicBoolean(false);
    /** Set when the test kills the follower processes (crash emulation). */
    static final AtomicBoolean CRASHED = new AtomicBoolean(false);
    static final AtomicBoolean FAIL_AT_UPTODATE = new AtomicBoolean(false);
    static volatile long newLeaderAckDelayMs = 0;
    static final AtomicInteger DELAYED_SYNC_THREADS = new AtomicInteger();
    static final ConcurrentLinkedQueue<String> SYNC_EXCEPTIONS = new ConcurrentLinkedQueue<>();

    /**
     * SyncRequestProcessor whose thread start is delayed (no logic change):
     * requests enqueued by logRequest stay in memory.  When the test crashes
     * the follower process (CRASHED), the thread dies with it without running,
     * i.e. the in-memory queue is lost exactly as in a process crash.
     */
    static class DelayedSyncRequestProcessor extends SyncRequestProcessor {
        DelayedSyncRequestProcessor(FollowerZooKeeperServer zks, RequestProcessor next) {
            super(zks, next);
        }

        @Override
        public void run() {
            if (SYNC_DELAY_ARMED.get()) {
                DELAYED_SYNC_THREADS.incrementAndGet();
            }
            while (SYNC_DELAY_ARMED.get() && !CRASHED.get()) {
                try {
                    Thread.sleep(20);
                } catch (InterruptedException e) {
                    return;
                }
            }
            if (CRASHED.get()) {
                return; // the process died before this thread wrote anything
            }
            super.run();
        }
    }

    static class CrashableFollowerZooKeeperServer extends FollowerZooKeeperServer {
        CrashableFollowerZooKeeperServer(FileTxnSnapLog logFactory, QuorumPeer self) throws IOException {
            super(logFactory, self, self.getZkDb());
        }

        @Override
        protected void setupRequestProcessors() {
            // Same chain as FollowerZooKeeperServer.setupRequestProcessors, with
            // the start-delayed SyncRequestProcessor.
            RequestProcessor finalProcessor = new FinalRequestProcessor(this);
            commitProcessor = new CommitProcessor(finalProcessor, Long.toString(getServerId()), true,
                                                  getZooKeeperServerListener());
            commitProcessor.start();
            firstProcessor = new FollowerRequestProcessor(this, commitProcessor);
            ((FollowerRequestProcessor) firstProcessor).start();
            syncProcessor = new DelayedSyncRequestProcessor(this, new SendAckRequestProcessor(getFollower()));
            syncProcessor.start();
        }
    }

    static class ReproQuorumPeer extends QuorumPeer {
        ReproQuorumPeer() throws SaslException {
        }

        @Override
        protected Follower makeFollower(FileTxnSnapLog logFactory) throws IOException {
            return new Follower(this, new CrashableFollowerZooKeeperServer(logFactory, this)) {
                private boolean delayed = false;

                @Override
                protected void syncWithLeader(long newLeaderZxid) throws Exception {
                    try {
                        super.syncWithLeader(newLeaderZxid);
                    } catch (Exception e) {
                        // observation only: record and rethrow unchanged
                        StackTraceElement top = e.getStackTrace().length > 0 ? e.getStackTrace()[0] : null;
                        SYNC_EXCEPTIONS.add("sid=" + self.getId() + " " + e.getClass().getName() + " at " + top);
                        throw e;
                    }
                }

                @Override
                void readPacket(QuorumPacket pp) throws IOException {
                    super.readPacket(pp);
                    if (FAIL_AT_UPTODATE.get() && pp.getType() == Leader.UPTODATE) {
                        throw new SocketTimeoutException("injected failure while reading UPTODATE");
                    }
                }

                @Override
                void writePacket(QuorumPacket pp, boolean flush) throws IOException {
                    if (pp != null && pp.getType() == Leader.ACK && (pp.getZxid() & 0xffffffffL) == 0
                        && !delayed && newLeaderAckDelayMs > 0) {
                        delayed = true;
                        try {
                            Thread.sleep(newLeaderAckDelayMs);
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                    }
                    super.writePacket(pp, flush);
                }
            };
        }
    }

    static class ReproMain extends TestQPMain {
        @Override
        protected QuorumPeer getQuorumPeer() throws SaslException {
            return new ReproQuorumPeer();
        }
    }

    private int[] clientPorts = new int[SERVER_COUNT];

    private void startEnsemble() throws Exception {
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
                    return new ReproMain();
                }
            };
            mt[i].start();
        }
        for (int i = 0; i < SERVER_COUNT; i++) {
            assertTrue(ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[i], CONNECTION_TIMEOUT),
                       "waiting for server " + i + " being up");
        }
    }

    private int findLeader() {
        for (int i = 0; i < mt.length; i++) {
            if (mt[i].main.quorumPeer != null && mt[i].main.quorumPeer.leader != null) {
                return i;
            }
        }
        return -1;
    }

    /**
     * Phase 1 of DIFFSyncConsistencyTest: shut both followers down and let the
     * leader log (but not commit) a create; returns the leader index.
     */
    private int leaderLogsUncommittedTxn(ZooKeeper[] zkHolder) throws Exception {
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
            fail("create /zk" + leader + " should have failed");
        } catch (KeeperException e) {
            // expected: no quorum
        }
        Proposal p = null;
        for (Proposal q : outstanding.values()) {
            if (q.request.getHdr().getType() == OpCode.create) {
                p = q;
            }
        }
        assertNotNull(p, "leader has no outstanding create proposal");
        long waited = 0;
        while (!p.qvAcksetPairs.get(0).getAckset().contains((long) leader)) {
            if (waited > 2000) {
                fail("leader did not force its own proposal");
            }
            Thread.sleep(100);
            waited += 100;
        }
        // Let the leader notice the lost quorum with the normal tick and step down
        // before the followers return, so that it is re-elected in a new epoch.
        mt[leader].main.quorumPeer.tickTime = previousTick;
        long end = System.currentTimeMillis() + 60_000;
        while (mt[leader].main.quorumPeer.getPeerState() == QuorumPeer.ServerState.LEADING
               && System.currentTimeMillis() < end) {
            Thread.sleep(100);
        }
        zkHolder[0] = zk;
        return leader;
    }

    private void restartFollowers(int leader) throws Exception {
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i == leader) {
                continue;
            }
            mt[i].start();
        }
    }

    private boolean leaderServes(ZooKeeper zk, String path, long timeoutMs) throws Exception {
        long end = System.currentTimeMillis() + timeoutMs;
        while (System.currentTimeMillis() < end) {
            try {
                Stat stat = zk.exists(path, false);
                if (stat != null) {
                    return true;
                }
            } catch (KeeperException.ConnectionLossException e) {
                // retry
            }
            Thread.sleep(100);
        }
        return false;
    }

    /**
     * D-1 / U-DUR.  Both followers acknowledge NEWLEADER of the re-elected
     * leader, which then serves the DIFF-synced transaction.  The followers'
     * SyncThreads are delayed (timing assistance) and the follower processes
     * crash after the NEWLEADER ACK (injected read failure at UPTODATE, then
     * the processes are killed: CRASHED), before their SyncThread wrote the
     * enqueued transaction.  The two followers then restart without the old
     * leader and elect a new leader.  Expected (Zab): the transaction that the
     * old leader served after the NEWLEADER quorum is still visible.
     */
    @Test
    @Timeout(value = 240)
    public void testServedTxnSurvivesFollowerCrashAfterNewLeaderAck() throws Exception {
        startEnsemble();
        ZooKeeper[] holder = new ZooKeeper[1];
        int leader = leaderLogsUncommittedTxn(holder);
        ZooKeeper zk = holder[0];
        SYNC_DELAY_ARMED.set(true);
        FAIL_AT_UPTODATE.set(true);
        restartFollowers(leader);
        boolean served = leaderServes(zk, "/zk" + leader, 30_000);
        LOG.info("SPECULAR-OBSERVATION old leader {} serves /zk{}: {}; delayed follower SyncThreads={}",
                 leader, leader, served, DELAYED_SYNC_THREADS.get());
        assertTrue(served, "old leader never served /zk" + leader + " (NEWLEADER quorum not reached)");
        // crash the follower processes: their delayed SyncThreads die unflushed
        CRASHED.set(true);
        for (int i = 0; i < SERVER_COUNT; i++) {
            mt[i].shutdown();
        }
        waitForOne(zk, States.CONNECTING);
        SYNC_DELAY_ARMED.set(false);
        FAIL_AT_UPTODATE.set(false);
        CRASHED.set(false);
        restartFollowers(leader);
        int newLeader = -1;
        long end = System.currentTimeMillis() + 60_000;
        while (newLeader < 0 && System.currentTimeMillis() < end) {
            Thread.sleep(200);
            newLeader = findLeader();
        }
        assertNotEquals(-1, newLeader, "no new leader elected");
        assertNotEquals(leader, newLeader, "new leader is still the old leader");
        zk.close();
        CountdownWatcher watch = new CountdownWatcher();
        zk = new ZooKeeper("127.0.0.1:" + clientPorts[newLeader], CONNECTION_TIMEOUT, watch);
        watch.waitForConnected(CONNECTION_TIMEOUT);
        Stat val = zk.exists("/zk" + leader, false);
        LOG.info("SPECULAR-OBSERVATION new leader {} (epoch {}) sees /zk{}: {}", newLeader,
                 mt[newLeader].main.quorumPeer.getCurrentEpoch(), leader, val != null);
        zk.close();
        assertNotNull(val, "Data inconsistency: /zk" + leader + " was served after the NEWLEADER quorum but is lost");
    }

    /**
     * D-2 / U-ACK.  Same setup; the followers' learner threads are delayed for
     * 3 s right before writing the NEWLEADER ACK (no crash, no failure).
     * Expected: the re-elected leader establishes its epoch with the first
     * NEWLEADER quorum and serves the transaction well before
     * initLimit * tickTime (40 s) expires.
     */
    @Test
    @Timeout(value = 240)
    public void testNewLeaderQuorumWithDelayedNewLeaderAck() throws Exception {
        startEnsemble();
        ZooKeeper[] holder = new ZooKeeper[1];
        int leader = leaderLogsUncommittedTxn(holder);
        ZooKeeper zk = holder[0];
        newLeaderAckDelayMs = 3000;
        long start = System.currentTimeMillis();
        restartFollowers(leader);
        boolean served = leaderServes(zk, "/zk" + leader, 25_000);
        long elapsed = System.currentTimeMillis() - start;
        long epoch = mt[leader].main.quorumPeer.getCurrentEpoch();
        LOG.info("SPECULAR-OBSERVATION served={} after {} ms; leader currentEpoch={} acceptedEpoch={}",
                 served, elapsed, epoch, mt[leader].main.quorumPeer.getAcceptedEpoch());
        newLeaderAckDelayMs = 0;
        zk.close();
        assertTrue(served, "re-elected leader did not establish its epoch within 25 s "
                   + "(NEWLEADER ACKs consumed as proposal ACKs?)");
    }

    /**
     * D-3 / U-NPE, Level 0 (no injection): a follower restarts and rejoins an
     * established leader while a client keeps writing.  Outstanding proposals
     * are forwarded before NEWLEADER (Leader.startForwarding) and their COMMITs
     * may arrive after it.  Expected: the follower synchronizes (BROADCAST)
     * without an exception in Learner.syncWithLeader.
     */
    @Test
    @Timeout(value = 180)
    public void testFollowerRejoinsEstablishedLeaderUnderLoad() throws Exception {
        startEnsemble();
        int leader = findLeader();
        int follower = (leader + 1) % SERVER_COUNT;
        CountdownWatcher watch = new CountdownWatcher();
        ZooKeeper zk = new ZooKeeper("127.0.0.1:" + clientPorts[leader], CONNECTION_TIMEOUT, watch);
        watch.waitForConnected(CONNECTION_TIMEOUT);
        AtomicBoolean stop = new AtomicBoolean(false);
        AtomicInteger issued = new AtomicInteger();
        java.util.concurrent.Semaphore window = new java.util.concurrent.Semaphore(200);
        Thread writer = new Thread(() -> {
            while (!stop.get()) {
                try {
                    window.acquire();
                } catch (InterruptedException e) {
                    return;
                }
                zk.create("/load-", new byte[16], Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT_SEQUENTIAL,
                          (rc, path, ctx, name) -> window.release(), null);
                issued.incrementAndGet();
            }
        });
        writer.start();
        int attempts = 0;
        int npe = 0;
        boolean synced = true;
        for (int round = 0; round < 5; round++) {
            mt[follower].shutdown();
            Thread.sleep(500);
            mt[follower].start();
            attempts++;
            long end = System.currentTimeMillis() + 20_000;
            boolean ok = false;
            while (System.currentTimeMillis() < end) {
                QuorumPeer qp = mt[follower].getQuorumPeer();
                if (qp != null && qp.getZabState() == QuorumPeer.ZabState.BROADCAST) {
                    ok = true;
                    break;
                }
                Thread.sleep(20);
            }
            synced &= ok;
            for (String e : SYNC_EXCEPTIONS) {
                if (e.contains("NullPointerException")) {
                    npe++;
                }
            }
            if (npe > 0) {
                break;
            }
        }
        stop.set(true);
        writer.join();
        LOG.info("SPECULAR-OBSERVATION rejoin attempts={} issuedWrites={} syncExceptions={} allSynced={}",
                 attempts, issued.get(), SYNC_EXCEPTIONS, synced);
        zk.close();
        assertTrue(npe == 0, "NullPointerException in Learner.syncWithLeader while rejoining: " + SYNC_EXCEPTIONS);
    }

    @BeforeEach
    public void resetInjection() {
        SYNC_EXCEPTIONS.clear();
        SYNC_DELAY_ARMED.set(false);
        CRASHED.set(false);
        FAIL_AT_UPTODATE.set(false);
        newLeaderAckDelayMs = 0;
        DELAYED_SYNC_THREADS.set(0);
    }

    @AfterEach
    public void tearDown() {
        SYNC_DELAY_ARMED.set(false);
        CRASHED.set(true);
        FAIL_AT_UPTODATE.set(false);
        newLeaderAckDelayMs = 0;
        for (int i = 0; i < mt.length; i++) {
            try {
                if (mt[i] != null) {
                    mt[i].shutdown();
                }
            } catch (InterruptedException e) {
                LOG.warn("interrupted", e);
            }
        }
    }
}
