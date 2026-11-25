/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements. See the NOTICE file
 * distributed with this work for additional information regarding copyright ownership.
 * The ASF licenses this file to You under the Apache License, Version 2.0.
 */
package org.apache.zookeeper.server.quorum;

import static org.junit.jupiter.api.Assertions.assertEquals;
import java.io.ByteArrayOutputStream;
import java.nio.ByteBuffer;
import java.util.ArrayList;
import java.util.List;
import org.apache.jute.BinaryOutputArchive;
import org.apache.jute.InputArchive;
import org.apache.jute.OutputArchive;
import org.apache.zookeeper.ZKTestCase;
import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.server.util.ZxidUtils;
import org.apache.zookeeper.txn.CreateSessionTxn;
import org.apache.zookeeper.txn.TxnHeader;
import org.junit.jupiter.api.Test;

/**
 * Specula V1 update-focused scenario (harness-only).  Derived from the update's
 * NEWLEADER branch: zk.startupWithoutServing() starts the SyncRequestProcessor /
 * SendAckRequestProcessor, every packetsNotCommitted entry is handed to
 * logRequest, and only then is the NEWLEADER ACK written.  The conversation
 * plays the leader side of Zab1_0Test#testNormalFollowerRunWithDiff with a
 * larger DIFF and records (without asserting an outcome) which ACK the learner
 * writes first after NEWLEADER, and whether the DIFF txns were fsynced when the
 * NEWLEADER ACK was written (NewLeaderAckSent probe).
 */
public class SpeculaNewLeaderAckOrderTest extends ZKTestCase {

    static final int DIFF_TXNS = Integer.getInteger("specula.diff.txns", 7);

    @Test
    public void testFirstAckAfterNewLeaderWithDiff() throws Exception {
        final List<Long> acksBeforeNewLeaderAck = new ArrayList<>();
        final long[] firstAck = new long[] {-1};
        new Zab1_0Test().testFollowerConversation(new Zab1_0Test.FollowerConversation() {
            @Override
            public void converseWithFollower(InputArchive ia, OutputArchive oa, Follower f) throws Exception {
                QuorumPacket qp = new QuorumPacket();
                Zab1_0Test.readPacketSkippingPing(ia, qp);
                assertEquals(Leader.FOLLOWERINFO, qp.getType());
                qp.setType(Leader.LEADERINFO);
                qp.setZxid(ZxidUtils.makeZxid(1, 0));
                byte[] protoBytes = new byte[4];
                ByteBuffer.wrap(protoBytes).putInt(0x10000);
                qp.setData(protoBytes);
                oa.writeRecord(qp, null);
                Zab1_0Test.readPacketSkippingPing(ia, qp);
                assertEquals(Leader.ACKEPOCH, qp.getType());

                qp.setType(Leader.DIFF);
                qp.setData(new byte[0]);
                qp.setZxid(ZxidUtils.makeZxid(1, DIFF_TXNS));
                oa.writeRecord(qp, null);
                for (int i = 1; i <= DIFF_TXNS; i++) {
                    long zxid = ZxidUtils.makeZxid(1, i);
                    proposeNewSession(qp, zxid, 0x300 + i);
                    oa.writeRecord(qp, null);
                    qp.setType(Leader.COMMIT);
                    qp.setZxid(zxid);
                    qp.setData(null);
                    oa.writeRecord(qp, null);
                }
                qp.setType(Leader.NEWLEADER);
                qp.setZxid(ZxidUtils.makeZxid(1, 0));
                qp.setData(null);
                oa.writeRecord(qp, null);

                // Read ACKs until the NEWLEADER ACK (zxid (1,0)) arrives.
                while (true) {
                    Zab1_0Test.readPacketSkippingPing(ia, qp);
                    assertEquals(Leader.ACK, qp.getType());
                    if (firstAck[0] == -1) {
                        firstAck[0] = qp.getZxid();
                    }
                    if (qp.getZxid() == ZxidUtils.makeZxid(1, 0)) {
                        break;
                    }
                    acksBeforeNewLeaderAck.add(qp.getZxid());
                }
                qp.setType(Leader.UPTODATE);
                qp.setZxid(0);
                oa.writeRecord(qp, null);
                // UPTODATE ACK (and any remaining txn ACKs)
                long deadline = System.currentTimeMillis() + 2000;
                int seen = 0;
                while (seen < DIFF_TXNS + 1 - acksBeforeNewLeaderAck.size() && System.currentTimeMillis() < deadline) {
                    Zab1_0Test.readPacketSkippingPing(ia, qp);
                    seen++;
                }
                System.out.println("SPECULA-ACK-ORDER diffTxns=" + DIFF_TXNS
                    + " firstAckZxid=0x" + Long.toHexString(firstAck[0])
                    + " txnAcksBeforeNewLeaderAck=" + acksBeforeNewLeaderAck.size());
            }
        });
    }

    private static void proposeNewSession(QuorumPacket qp, long zxid, long sessionId) throws Exception {
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
}
