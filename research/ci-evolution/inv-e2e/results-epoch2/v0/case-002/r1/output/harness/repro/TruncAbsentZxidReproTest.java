/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file distributed
 * with this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.server.quorum.ZabUtils.createQuorumPeer;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNull;
import java.io.File;
import java.io.IOException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.util.concurrent.ConcurrentHashMap;
import org.apache.jute.BinaryInputArchive;
import org.apache.jute.BinaryOutputArchive;
import org.apache.jute.InputArchive;
import org.apache.jute.OutputArchive;
import org.apache.zookeeper.ZKTestCase;
import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.server.DataTree;
import org.apache.zookeeper.server.Request;
import org.apache.zookeeper.server.ZKDatabase;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.server.quorum.QuorumPeer.QuorumServer;
import org.apache.zookeeper.server.util.ZxidUtils;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.TestUtils;
import org.apache.zookeeper.txn.CreateTxn;
import org.apache.zookeeper.txn.TxnHeader;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

/**
 * Specula reproduction for model counterexample MC-3 (update-independent).
 * A learner whose log holds an uncommitted txn (1,1) syncs with a newly
 * elected, empty leader.  LearnerHandler.syncFollower sends TRUNC with the
 * leader's maxCommittedLog (= lastProcessedZxid = 0 for an empty committed
 * log, peerLastZxid 0x100000001 > 0).  The scripted leader below sends exactly
 * that stream; the test then inspects the learner's DataTree.
 */
public class TruncAbsentZxidReproTest extends ZKTestCase {

    private static final Logger LOG = LoggerFactory.getLogger(TruncAbsentZxidReproTest.class);

    static class ScriptedFollower extends Follower {
        QuorumServer leaderQS;
        ScriptedFollower(QuorumPeer self, FollowerZooKeeperServer zk) {
            super(self, zk);
        }
        @Override
        protected QuorumServer findLeader() {
            return leaderQS;
        }
    }

    @Test
    @Timeout(value = 120)
    public void truncToZeroKeepsUncommittedEntry() throws Exception {
        File tmpDir = File.createTempFile("test", "dir", ClientBase.testBaseDir);
        tmpDir.delete();
        tmpDir.mkdir();
        Thread followerThread = null;
        ScriptedFollower follower = null;
        QuorumPeer peer = null;
        try {
            // Learner storage: empty snapshot at 0, then an uncommitted create at (1,1).
            FileTxnSnapLog seed = new FileTxnSnapLog(tmpDir, tmpDir);
            seed.save(new DataTree(), new ConcurrentHashMap<Long, Integer>(), false);
            long orphanZxid = ZxidUtils.makeZxid(1, 1);
            TxnHeader hdr = new TxnHeader(0x1234, 1, orphanZxid, 33, ZooDefs.OpCode.create);
            CreateTxn ct = new CreateTxn("/orphan", "x".getBytes(), ZooDefs.Ids.OPEN_ACL_UNSAFE, false, 1);
            seed.append(new Request(0x1234, 1, ZooDefs.OpCode.create, hdr, ct, orphanZxid));
            seed.commit();
            seed.close();

            peer = createQuorumPeer(tmpDir);
            FileTxnSnapLog logFactory = new FileTxnSnapLog(tmpDir, tmpDir);
            peer.setTxnFactory(logFactory);
            ZKDatabase zkDb = new ZKDatabase(logFactory);
            peer.setZKDatabase(zkDb);
            // The learner took part in epoch 1 (its log holds an epoch-1 txn).
            peer.setAcceptedEpoch(1);
            peer.setCurrentEpoch(1);
            follower = new ScriptedFollower(peer, new FollowerZooKeeperServer(logFactory, peer, zkDb));
            peer.follower = follower;
            ServerSocket ss = new ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"));
            follower.leaderQS = new QuorumServer(1, (InetSocketAddress) ss.getLocalSocketAddress());
            final Follower f = follower;
            followerThread = new Thread(() -> {
                try {
                    f.followLeader();
                } catch (Exception e) {
                    LOG.warn("follower thread", e);
                }
            });
            followerThread.start();
            Socket s = ss.accept();
            InputArchive ia = BinaryInputArchive.getArchive(s.getInputStream());
            OutputArchive oa = BinaryOutputArchive.getArchive(s.getOutputStream());

            QuorumPacket qp = new QuorumPacket();
            readSkippingPing(ia, qp);
            assertEquals(Leader.FOLLOWERINFO, qp.getType());
            LOG.info("REPRO: learner FOLLOWERINFO zxid=0x{}", Long.toHexString(qp.getZxid()));

            qp.setType(Leader.LEADERINFO);
            qp.setZxid(ZxidUtils.makeZxid(2, 0));
            byte[] proto = new byte[4];
            ByteBuffer.wrap(proto).putInt(0x10000);
            qp.setData(proto);
            oa.writeRecord(qp, null);
            readSkippingPing(ia, qp);
            assertEquals(Leader.ACKEPOCH, qp.getType());
            LOG.info("REPRO: learner ACKEPOCH lastLoggedZxid=0x{}", Long.toHexString(qp.getZxid()));
            assertEquals(orphanZxid, qp.getZxid());

            // Empty leader: maxCommittedLog = lastProcessedZxid = 0 -> TRUNC 0.
            oa.writeRecord(new QuorumPacket(Leader.TRUNC, 0, null, null), null);
            oa.writeRecord(new QuorumPacket(Leader.NEWLEADER, ZxidUtils.makeZxid(2, 0), null, null), null);
            oa.writeRecord(new QuorumPacket(Leader.UPTODATE, 0, null, null), null);
            readSkippingPing(ia, qp);
            assertEquals(Leader.ACK, qp.getType());
            readSkippingPing(ia, qp);
            assertEquals(Leader.ACK, qp.getType());

            long tail = new FileTxnSnapLog(tmpDir, tmpDir).getLastLoggedZxid();
            boolean orphanInTree = follower.fzk.getZKDatabase().getNode("/orphan") != null;
            long lastProcessed = follower.fzk.getZKDatabase().getDataTreeLastProcessedZxid();
            LOG.info("REPRO RESULT: after TRUNC 0 log tail=0x{} tree lastProcessed=0x{} /orphan in tree={}",
                     Long.toHexString(tail), Long.toHexString(lastProcessed), orphanInTree);
            assertNull(follower.fzk.getZKDatabase().getNode("/orphan"),
                       "learner still serves the uncommitted /orphan after TRUNC to 0");
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

    private static void readSkippingPing(InputArchive ia, QuorumPacket qp) throws IOException {
        while (true) {
            ia.readRecord(qp, null);
            if (qp.getType() != Leader.PING) {
                return;
            }
        }
    }
}
