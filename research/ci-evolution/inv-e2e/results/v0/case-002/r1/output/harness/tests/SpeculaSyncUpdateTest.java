/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file distributed
 * with this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.server.quorum.ZabUtils.createQuorumPeer;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.spy;
import java.io.ByteArrayOutputStream;
import java.io.EOFException;
import java.io.File;
import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
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
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.TestUtils;
import org.apache.zookeeper.txn.CreateSessionTxn;
import org.apache.zookeeper.txn.TxnHeader;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Specula update-focused learner synchronization scenarios.  A test thread
 * plays the leader's LearnerHandler packet stream (as Zab1_0Test does) so the
 * exact packet order that Leader.startForwarding / LearnerHandler.run can
 * produce is replayed deterministically against the real Learner code.
 */
public class SpeculaSyncUpdateTest extends ZKTestCase {

    private static final Logger LOG = LoggerFactory.getLogger(SpeculaSyncUpdateTest.class);

    interface Conversation {
        void converse(InputArchive ia, OutputArchive oa, Zab1_0Test.ConversableFollower f, File dataDir) throws Exception;
    }

    private void runConversation(Conversation c, ZKDatabase[] dbHolder, boolean spyDb) throws Exception {
        File tmpDir = ClientBase.createTmpDir();
        Thread followerThread = null;
        Zab1_0Test.ConversableFollower follower = null;
        QuorumPeer peer = null;
        try {
            peer = createQuorumPeer(tmpDir);
            FileTxnSnapLog logFactory = new FileTxnSnapLog(tmpDir, tmpDir);
            peer.setTxnFactory(logFactory);
            ZKDatabase zkDb = new ZKDatabase(logFactory);
            if (spyDb) {
                zkDb = spy(zkDb);
            }
            if (dbHolder != null) {
                dbHolder[0] = zkDb;
            }
            FollowerZooKeeperServer zk = new FollowerZooKeeperServer(logFactory, peer, zkDb);
            peer.setZKDatabase(zkDb);
            follower = new Zab1_0Test.ConversableFollower(peer, zk);
            peer.follower = follower;
            ServerSocket ss = new ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"));
            QuorumServer leaderQS = new QuorumServer(1, (InetSocketAddress) ss.getLocalSocketAddress());
            follower.setLeaderQuorumServer(leaderQS);
            final Follower followerForThread = follower;
            followerThread = new Thread(() -> {
                try {
                    followerForThread.followLeader();
                } catch (InterruptedException e) {
                    LOG.info("Follower thread interrupted", e);
                } catch (Exception e) {
                    LOG.warn("Unexpected exception in follower thread", e);
                }
            });
            followerThread.start();
            Socket leaderSocket = ss.accept();
            leaderSocket.setSoTimeout(10000);
            InputArchive ia = BinaryInputArchive.getArchive(leaderSocket.getInputStream());
            OutputArchive oa = BinaryOutputArchive.getArchive(leaderSocket.getOutputStream());
            c.converse(ia, oa, follower, tmpDir);
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

    private static void handshake(InputArchive ia, OutputArchive oa, long epoch) throws IOException {
        QuorumPacket qp = new QuorumPacket();
        Zab1_0Test.readPacketSkippingPing(ia, qp);
        assertEquals(Leader.FOLLOWERINFO, qp.getType());
        qp.setType(Leader.LEADERINFO);
        qp.setZxid(ZxidUtils.makeZxid(epoch, 0));
        byte[] protoBytes = new byte[4];
        ByteBuffer.wrap(protoBytes).putInt(0x10000);
        qp.setData(protoBytes);
        oa.writeRecord(qp, null);
        Zab1_0Test.readPacketSkippingPing(ia, qp);
        assertEquals(Leader.ACKEPOCH, qp.getType());
    }

    private static QuorumPacket proposal(long zxid, long sessionId) throws IOException {
        QuorumPacket qp = new QuorumPacket();
        qp.setType(Leader.PROPOSAL);
        qp.setZxid(zxid);
        TxnHeader hdr = new TxnHeader(sessionId, 1414, zxid, 55, ZooDefs.OpCode.createSession);
        CreateSessionTxn cst = new CreateSessionTxn(30000);
        ByteArrayOutputStream baos = new ByteArrayOutputStream();
        OutputArchive boa = BinaryOutputArchive.getArchive(baos);
        boa.writeRecord(hdr, null);
        boa.writeRecord(cst, null);
        qp.setData(baos.toByteArray());
        return qp;
    }

    private static void send(OutputArchive oa, int type, long zxid) throws IOException {
        oa.writeRecord(new QuorumPacket(type, zxid, null, null), null);
    }

    private static long lastLoggedOnDisk(File dataDir) throws IOException {
        FileTxnSnapLog fresh = new FileTxnSnapLog(dataDir, dataDir);
        try {
            return fresh.getLastLoggedZxid();
        } finally {
            fresh.close();
        }
    }

    /**
     * Scenario U-NPE: an established leader forwards an outstanding proposal P
     * (Leader.startForwarding) before queueing NEWLEADER, and P's COMMIT is
     * forwarded after NEWLEADER (quorum ACKs from other followers arrive
     * meanwhile).  The learner must accept the COMMIT and finish synchronization.
     */
    @Test
    @Timeout(value = 60)
    public void testCommitOfForwardedProposalAfterNewLeader() throws Exception {
        final List<String> observed = new ArrayList<>();
        runConversation((ia, oa, f, dataDir) -> {
            final long epoch = 1;
            final long p = ZxidUtils.makeZxid(epoch, 1);
            handshake(ia, oa, epoch);
            send(oa, Leader.DIFF, 0);                       // follower already in sync with committed log
            oa.writeRecord(proposal(p, 0x333), null);         // outstanding proposal forwarded by startForwarding
            send(oa, Leader.NEWLEADER, ZxidUtils.makeZxid(epoch, 0));
            send(oa, Leader.COMMIT, p);                       // commit reaches quorum after NEWLEADER was queued
            send(oa, Leader.UPTODATE, 0);
            boolean newLeaderAck = false;
            boolean upToDateAck = false;
            try {
                QuorumPacket qp = new QuorumPacket();
                while (!(newLeaderAck && upToDateAck)) {
                    Zab1_0Test.readPacketSkippingPing(ia, qp);
                    observed.add(Leader.getPacketType(qp.getType()) + ":" + Long.toHexString(qp.getZxid()));
                    if (qp.getType() == Leader.ACK && qp.getZxid() == ZxidUtils.makeZxid(epoch, 0)) {
                        if (!newLeaderAck) {
                            newLeaderAck = true;
                        } else {
                            upToDateAck = true;
                        }
                    }
                }
            } catch (EOFException | SocketTimeoutException | java.net.SocketException e) {
                observed.add("stream-ended:" + e.getClass().getSimpleName());
            }
            LOG.info("SPECULA observed learner packets {}", observed);
            long deadline = System.currentTimeMillis() + 5000;
            while ((f.fzk.getLastProcessedZxid() != p || f.self.getZabState() != QuorumPeer.ZabState.BROADCAST)
                   && System.currentTimeMillis() < deadline) {
                Thread.sleep(10);
            }
            LOG.info("SPECULA outcome newLeaderAck={} upToDateAck={} zabState={} lastProcessed=0x{}",
                newLeaderAck, upToDateAck, f.self.getZabState(), Long.toHexString(f.fzk.getLastProcessedZxid()));
            assertTrue(newLeaderAck, "learner must ACK NEWLEADER; observed " + observed);
            assertTrue(upToDateAck, "learner must finish synchronization and ACK UPTODATE; observed " + observed);
            assertEquals(QuorumPeer.ZabState.BROADCAST, f.self.getZabState());
            assertEquals(p, f.fzk.getLastProcessedZxid(), "committed forwarded proposal must be applied");
        }, null, false);
    }

    /**
     * Scenario U-DUR: DIFF synchronization of a committed-log entry X followed by
     * NEWLEADER.  The learner's transaction-log fsync is delayed (slow disk).
     * The NEWLEADER ACK makes the leader count this learner in the quorum that
     * establishes the new epoch, so X and the new current epoch must not be
     * persisted out of order with that ACK.
     */
    @Test
    @Timeout(value = 60)
    public void testNewLeaderAckOnlyAfterDiffTxnDurable() throws Exception {
        final ZKDatabase[] holder = new ZKDatabase[1];
        final CountDownLatch release = new CountDownLatch(1);
        runConversation((ia, oa, f, dataDir) -> {
            ZKDatabase db = holder[0];
            doAnswer(inv -> {
                release.await(30, TimeUnit.SECONDS);       // slow fsync: SyncRequestProcessor.flush -> ZKDatabase.commit
                return inv.callRealMethod();
            }).when(db).commit();
            final long epoch = 1;
            final long x = ZxidUtils.makeZxid(epoch, 1);
            handshake(ia, oa, epoch);
            send(oa, Leader.DIFF, x);
            oa.writeRecord(proposal(x, 0x444), null);
            send(oa, Leader.COMMIT, x);
            send(oa, Leader.NEWLEADER, ZxidUtils.makeZxid(epoch, 0));
            QuorumPacket qp = new QuorumPacket();
            boolean ackBeforeDurable = false;
            long onDiskAtAck = -1;
            long currentEpochAtAck = -1;
            try {
                Zab1_0Test.readPacketSkippingPing(ia, qp);
                assertEquals(Leader.ACK, qp.getType());
                assertEquals(ZxidUtils.makeZxid(epoch, 0), qp.getZxid());
                onDiskAtAck = lastLoggedOnDisk(dataDir);
                currentEpochAtAck = f.self.getCurrentEpoch();
                ackBeforeDurable = onDiskAtAck != x;
            } catch (SocketTimeoutException e) {
                LOG.info("SPECULA learner withheld NEWLEADER ACK while its log was not durable");
            }
            LOG.info("SPECULA at NEWLEADER ACK: onDisk=0x{} currentEpoch={} ackBeforeDurable={}",
                Long.toHexString(onDiskAtAck), currentEpochAtAck, ackBeforeDurable);
            release.countDown();
            send(oa, Leader.UPTODATE, 0);
            long deadline = System.currentTimeMillis() + 5000;
            while (lastLoggedOnDisk(dataDir) != x && System.currentTimeMillis() < deadline) {
                Thread.sleep(10);
            }
            assertEquals(x, lastLoggedOnDisk(dataDir), "X must eventually be durable");
            assertTrue(!ackBeforeDurable, "NEWLEADER was ACKed (currentEpoch=" + currentEpochAtAck
                + ") while the DIFF transaction 0x" + Long.toHexString(x) + " was not yet on disk (disk last=0x"
                + Long.toHexString(onDiskAtAck) + ")");
        }, holder, true);
    }
}
