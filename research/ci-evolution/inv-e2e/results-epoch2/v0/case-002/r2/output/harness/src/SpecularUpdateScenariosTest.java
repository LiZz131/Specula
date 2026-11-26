/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file
 * distributed with this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.server.quorum.ZabUtils.createQuorumPeer;
import static org.junit.jupiter.api.Assertions.assertEquals;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicBoolean;
import org.apache.jute.BinaryInputArchive;
import org.apache.jute.BinaryOutputArchive;
import org.apache.jute.InputArchive;
import org.apache.jute.OutputArchive;
import org.apache.zookeeper.ZKTestCase;
import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.server.ZKDatabase;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.server.quorum.QuorumPeer.QuorumServer;
import org.apache.zookeeper.server.util.ZxidUtils;
import org.apache.zookeeper.test.TestUtils;
import org.apache.zookeeper.txn.CreateSessionTxn;
import org.apache.zookeeper.txn.TxnHeader;
import org.junit.jupiter.api.Test;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Specular update-focused learner conversations.  A test-side "leader" speaks
 * the real Zab 1.0 wire protocol to a real Follower (the same fixture style as
 * Zab1_0Test#testFollowerConversation).  Each scenario is derived from the
 * visible update to Learner.syncWithLeader (NEWLEADER now starts the follower
 * pipeline, logs and clears packetsNotCommitted, then ACKs).
 *
 * The tests record what the implementation does and assert the protocol
 * expectation that the unchanged leader side relies on.  They are run by
 * harness/run.sh for trace collection (a failing assertion does not prevent
 * the trace from being kept) and by the reproduction scripts.
 */
public class SpecularUpdateScenariosTest extends ZKTestCase {

    private static final Logger LOG = LoggerFactory.getLogger(SpecularUpdateScenariosTest.class);
    private static final File TEST_DATA = new File(System.getProperty("test.data.dir", "src/test/resources/data"));

    interface Conversation {
        void converse(InputArchive ia, OutputArchive oa, DelayingFollower f) throws Exception;
    }

    /** Real Follower whose NEWLEADER-ACK write can be delayed (scheduling delay injection). */
    static class DelayingFollower extends Follower {
        QuorumServer leaderQuorumServer;
        volatile long newLeaderAckDelayMs = 0;
        final AtomicBoolean newLeaderAckDelayed = new AtomicBoolean(false);
        final List<Throwable> followLeaderErrors = new ArrayList<>();

        DelayingFollower(QuorumPeer self, FollowerZooKeeperServer zk) {
            super(self, zk);
        }

        @Override
        protected QuorumServer findLeader() {
            return leaderQuorumServer;
        }

        @Override
        void writePacket(QuorumPacket pp, boolean flush) throws IOException {
            if (pp != null && pp.getType() == Leader.ACK && (pp.getZxid() & 0xffffffffL) == 0
                && newLeaderAckDelayMs > 0 && newLeaderAckDelayed.compareAndSet(false, true)) {
                // First zero-counter ACK written by the learner thread is the
                // NEWLEADER ACK (Learner.java:760).  Delay only that write.
                try {
                    Thread.sleep(newLeaderAckDelayMs);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            super.writePacket(pp, flush);
        }
    }

    static void readSkippingPing(InputArchive ia, QuorumPacket qp) throws IOException {
        while (true) {
            ia.readRecord(qp, null);
            if (qp.getType() != Leader.PING) {
                return;
            }
        }
    }

    private static volatile Socket leaderSide;

    private void runConversation(long nlAckDelayMs, Conversation conversation) throws Exception {
        File tmpDir = File.createTempFile("test", "dir", TEST_DATA);
        tmpDir.delete();
        tmpDir.mkdir();
        Thread followerThread = null;
        DelayingFollower follower = null;
        QuorumPeer peer = null;
        try {
            peer = createQuorumPeer(tmpDir);
            FileTxnSnapLog logFactory = new FileTxnSnapLog(tmpDir, tmpDir);
            peer.setTxnFactory(logFactory);
            ZKDatabase zkDb = new ZKDatabase(logFactory);
            FollowerZooKeeperServer zk = new FollowerZooKeeperServer(logFactory, peer, zkDb);
            peer.setZKDatabase(zkDb);
            follower = new DelayingFollower(peer, zk);
            follower.newLeaderAckDelayMs = nlAckDelayMs;
            peer.follower = follower;
            ServerSocket ss = new ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"));
            follower.leaderQuorumServer = new QuorumServer(1, (InetSocketAddress) ss.getLocalSocketAddress());
            final DelayingFollower f = follower;
            followerThread = new Thread(() -> {
                try {
                    f.followLeader();
                } catch (Throwable e) {
                    synchronized (f.followLeaderErrors) {
                        f.followLeaderErrors.add(e);
                    }
                    LOG.warn("Follower thread ended with exception", e);
                }
            });
            followerThread.start();
            Socket leaderSocket = ss.accept();
            leaderSide = leaderSocket;
            InputArchive ia = BinaryInputArchive.getArchive(leaderSocket.getInputStream());
            OutputArchive oa = BinaryOutputArchive.getArchive(leaderSocket.getOutputStream());
            conversation.converse(ia, oa, follower);
        } finally {
            if (follower != null) {
                follower.shutdown();
            }
            if (followerThread != null) {
                followerThread.interrupt();
                followerThread.join();
            }
            if (peer != null) {
                peer.shutdown();
            }
            TestUtils.deleteFileRecursively(tmpDir);
        }
    }

    /** FOLLOWERINFO -> LEADERINFO(epoch 1) -> ACKEPOCH, exactly as Zab1_0Test. */
    static void discovery(InputArchive ia, OutputArchive oa, QuorumPacket qp) throws IOException {
        readSkippingPing(ia, qp);
        assertEquals(Leader.FOLLOWERINFO, qp.getType());
        qp.setType(Leader.LEADERINFO);
        qp.setZxid(ZxidUtils.makeZxid(1, 0));
        byte[] protoBytes = new byte[4];
        ByteBuffer.wrap(protoBytes).putInt(0x10000);
        qp.setData(protoBytes);
        oa.writeRecord(qp, null);
        readSkippingPing(ia, qp);
        assertEquals(Leader.ACKEPOCH, qp.getType());
    }

    static void proposal(QuorumPacket qp, long zxid, long sessionId) throws IOException {
        qp.setType(Leader.PROPOSAL);
        qp.setZxid(zxid);
        TxnHeader hdr = new TxnHeader(sessionId, 1414, zxid, 55, ZooDefs.OpCode.createSession);
        CreateSessionTxn cst = new CreateSessionTxn(30000);
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        OutputArchive boa = BinaryOutputArchive.getArchive(baos);
        boa.writeRecord(hdr, null);
        boa.writeRecord(cst, null);
        qp.setData(baos.toByteArray());
    }

    static void send(OutputArchive oa, int type, long zxid) throws IOException {
        oa.writeRecord(new QuorumPacket(type, zxid, null, null), null);
    }

    /**
     * Scenario "diff-commit-after-newleader": an established leader forwards an
     * outstanding PROPOSAL before NEWLEADER (Leader.startForwarding) and its
     * COMMIT after NEWLEADER, before UPTODATE.  Expected (protocol): the
     * learner completes synchronization and ACKs UPTODATE.
     */
    @Test
    public void testCommitAfterNewLeaderForPreNewLeaderProposal() throws Exception {
        final long[] observed = new long[2];
        runConversation(0, (ia, oa, f) -> {
            QuorumPacket qp = new QuorumPacket();
            discovery(ia, oa, qp);
            long p1 = ZxidUtils.makeZxid(1, 1);
            send(oa, Leader.DIFF, 0);
            proposal(qp, p1, 0x333);
            oa.writeRecord(qp, null);
            send(oa, Leader.NEWLEADER, ZxidUtils.makeZxid(1, 0));
            send(oa, Leader.COMMIT, p1);
            send(oa, Leader.UPTODATE, 0);
            // Collect every ACK the learner writes until the stream ends or 3 s pass.
            List<Long> acks = new ArrayList<>();
            long end = System.currentTimeMillis() + 3000;
            try {
                while (System.currentTimeMillis() < end && acks.size() < 3) {
                    readSkippingPing(ia, qp);
                    if (qp.getType() == Leader.ACK) {
                        acks.add(qp.getZxid());
                    }
                }
            } catch (IOException e) {
                LOG.info("Learner closed the connection after {} ACKs: {}", acks.size(), e.toString());
            }
            LOG.info("SPECULAR-OBSERVATION commit-after-newleader acks={} followerErrors={} zabState={}",
                     acks, f.followLeaderErrors, f.self.getZabState());
            observed[0] = acks.size();
            observed[1] = f.self.getZabState() == QuorumPeer.ZabState.BROADCAST ? 1 : 0;
        });
        // Protocol expectation: NEWLEADER ACK, PROPOSAL ACK and UPTODATE ACK, broadcast reached.
        assertEquals(1, observed[1], "learner did not reach BROADCAST after a COMMIT that followed NEWLEADER");
    }

    /**
     * Scenario "diff-ack-before-newleader-ack": DIFF with one committed
     * proposal; the learner thread is delayed between logging the buffered
     * proposal and writing its NEWLEADER ACK.  LearnerHandler.run:609-623
     * treats the first ACK after NEWLEADER as the NEWLEADER ACK.
     */
    @Test
    public void testProposalAckBeforeNewLeaderAck() throws Exception {
        final long[] firstAck = new long[1];
        runConversation(1500, (ia, oa, f) -> {
            QuorumPacket qp = new QuorumPacket();
            discovery(ia, oa, qp);
            long p1 = ZxidUtils.makeZxid(1, 1);
            send(oa, Leader.DIFF, 0);
            proposal(qp, p1, 0x444);
            oa.writeRecord(qp, null);
            send(oa, Leader.COMMIT, p1);
            send(oa, Leader.NEWLEADER, ZxidUtils.makeZxid(1, 0));
            readSkippingPing(ia, qp);
            firstAck[0] = qp.getZxid();
            LOG.info("SPECULAR-OBSERVATION first packet after NEWLEADER type={} zxid=0x{}",
                     qp.getType(), Long.toHexString(qp.getZxid()));
            send(oa, Leader.UPTODATE, 0);
            List<Long> rest = new ArrayList<>();
            long end = System.currentTimeMillis() + 3000;
            try {
                while (System.currentTimeMillis() < end && rest.size() < 2) {
                    readSkippingPing(ia, qp);
                    rest.add(qp.getZxid());
                }
            } catch (IOException e) {
                LOG.info("stream ended: {}", e.toString());
            }
            LOG.info("SPECULAR-OBSERVATION later ACK zxids={}", rest);
        });
        assertEquals(ZxidUtils.makeZxid(1, 0), firstAck[0],
                     "first ACK after NEWLEADER is not the NEWLEADER ACK (LearnerHandler would discard it)");
    }

    static long liveThreads(String prefix) {
        long n = 0;
        for (Thread t : Thread.getAllStackTraces().keySet()) {
            if (t.isAlive() && t.getName().startsWith(prefix)) {
                n++;
            }
        }
        return n;
    }

    /**
     * D-5 / U-LEAK: the connection to the leader is lost after NEWLEADER and
     * before UPTODATE (the learner is INITIAL).  QuorumPeer then calls
     * Follower.shutdown(), as it does after every followLeader().  Expected:
     * the follower's request-processor threads are stopped.
     */
    @Test
    public void testShutdownAfterFailureBetweenNewLeaderAndUpToDate() throws Exception {
        final long[] leaked = new long[2];
        runConversation(0, (ia, oa, f) -> {
            QuorumPacket qp = new QuorumPacket();
            long before = liveThreads("SyncThread:0") + liveThreads("CommitProcessor:0");
            discovery(ia, oa, qp);
            long p1 = ZxidUtils.makeZxid(1, 1);
            send(oa, Leader.DIFF, 0);
            proposal(qp, p1, 0x555);
            oa.writeRecord(qp, null);
            send(oa, Leader.COMMIT, p1);
            send(oa, Leader.NEWLEADER, ZxidUtils.makeZxid(1, 0));
            readSkippingPing(ia, qp);           // NEWLEADER ACK or proposal ACK
            leaderSide.setSoTimeout(2000);
            try {
                readSkippingPing(ia, qp);       // the other one (updated code): the SyncThread is now idle
            } catch (java.net.SocketTimeoutException e) {
                LOG.info("no second ACK before UPTODATE (no learner pipeline yet)");
            }
            Thread.sleep(300);
            leaderSide.close();               // connection loss before UPTODATE
            long end = System.currentTimeMillis() + 5000;
            while (f.self.getZabState() == QuorumPeer.ZabState.SYNCHRONIZATION && System.currentTimeMillis() < end
                   && (f.sock == null || !f.sock.isClosed())) {
                Thread.sleep(20);
            }
            Thread.sleep(500);
            f.shutdown();                       // what QuorumPeer.run does after followLeader()
            Thread.sleep(1000);
            leaked[0] = liveThreads("SyncThread:0");
            leaked[1] = liveThreads("CommitProcessor:0");
            LOG.info("SPECULAR-OBSERVATION after Follower.shutdown(): SyncThread alive={} CommitProcessor alive={} (before sync: {}) zk.isRunning={}",
                     leaked[0], leaked[1], before, f.zk.isRunning());
        });
        assertEquals(0, leaked[0] + leaked[1], "request-processor threads leaked after Follower.shutdown()");
    }

    /**
     * D-4: a pre-Zab1.0 leader sends NEWLEADER during discovery and then
     * DIFF ... UPTODATE (no NEWLEADER in the sync loop).  Expected: the learner
     * starts its server and logs the synchronized proposal.
     */
    @Test
    public void testPreZab10LeaderSync() throws Exception {
        final boolean[] ok = new boolean[1];
        runConversation(0, (ia, oa, f) -> {
            QuorumPacket qp = new QuorumPacket();
            readSkippingPing(ia, qp);
            assertEquals(Leader.FOLLOWERINFO, qp.getType());
            send(oa, Leader.NEWLEADER, ZxidUtils.makeZxid(1, 0));   // pre-1.0 discovery
            long p1 = ZxidUtils.makeZxid(1, 1);
            send(oa, Leader.DIFF, 0);
            proposal(qp, p1, 0x666);
            oa.writeRecord(qp, null);
            send(oa, Leader.COMMIT, p1);
            send(oa, Leader.UPTODATE, 0);
            long end = System.currentTimeMillis() + 3000;
            while (System.currentTimeMillis() < end && f.self.getZabState() != QuorumPeer.ZabState.BROADCAST) {
                Thread.sleep(20);
            }
            Thread.sleep(300);
            ok[0] = f.self.getZabState() == QuorumPeer.ZabState.BROADCAST && f.zk.isRunning();
            LOG.info("SPECULAR-OBSERVATION pre-1.0 sync: zabState={} zk.isRunning={} followLeaderErrors={}",
                     f.self.getZabState(), f.zk.isRunning(), f.followLeaderErrors);
        });
        assertEquals(true, ok[0], "learner did not reach a running BROADCAST state after a pre-Zab1.0 sync");
    }
}
