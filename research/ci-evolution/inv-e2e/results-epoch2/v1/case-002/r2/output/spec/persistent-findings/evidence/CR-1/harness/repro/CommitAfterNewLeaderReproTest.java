/*
 * Specular code-review candidate CR-1 (case-002, run incr-8c80add29fe2).
 * Claim: the update clears packetsNotCommitted at NEWLEADER (Learner.java:757).
 * A COMMIT that the leader forwards after queuing NEWLEADER for a PROPOSAL it
 * forwarded before NEWLEADER (LearnerHandler queues NEWLEADER after
 * startForwarding, LearnerHandler.java:551,596-599) then reaches
 * `pif = packetsNotCommitted.peekFirst(); pif.hdr...` with pif == null
 * (Learner.java:645-647), aborting synchronization.
 * Level 0: legitimate leader packet sequence through the real learner code
 * (Zab1_0Test fake-leader conversation harness); no delays, no injection.
 */
package org.apache.zookeeper.server.quorum;

import static org.junit.jupiter.api.Assertions.assertEquals;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.ByteBuffer;
import org.apache.jute.BinaryOutputArchive;
import org.apache.jute.InputArchive;
import org.apache.jute.OutputArchive;
import org.apache.zookeeper.ZooDefs;
import org.apache.zookeeper.server.util.ZxidUtils;
import org.apache.zookeeper.txn.CreateSessionTxn;
import org.apache.zookeeper.txn.TxnHeader;
import org.junit.jupiter.api.Test;

public class CommitAfterNewLeaderReproTest extends Zab1_0Test {

    @Test
    public void testCommitForwardedBetweenNewLeaderAndUptodate() throws Exception {
        testFollowerConversation(new FollowerConversation() {
            @Override
            public void converseWithFollower(InputArchive ia, OutputArchive oa, Follower f) throws Exception {
                QuorumPacket qp = new QuorumPacket();
                readPacketSkippingPing(ia, qp);
                assertEquals(Leader.FOLLOWERINFO, qp.getType());
                qp.setType(Leader.LEADERINFO);
                qp.setZxid(ZxidUtils.makeZxid(1, 0));
                byte[] protoBytes = new byte[4];
                ByteBuffer.wrap(protoBytes).putInt(0x10000);
                qp.setData(protoBytes);
                oa.writeRecord(qp, null);
                readPacketSkippingPing(ia, qp);
                assertEquals(Leader.ACKEPOCH, qp.getType());

                // DIFF (empty learner), then the outstanding PROPOSAL forwarded by startForwarding.
                qp.setType(Leader.DIFF);
                qp.setData(new byte[0]);
                qp.setZxid(0);
                oa.writeRecord(qp, null);
                long zxid = ZxidUtils.makeZxid(1, 1);
                qp.setType(Leader.PROPOSAL);
                qp.setZxid(zxid);
                TxnHeader hdr = new TxnHeader(4, 1414, zxid, 55, ZooDefs.OpCode.createSession);
                ByteArrayOutputStream baos = new ByteArrayOutputStream();
                BinaryOutputArchive boa = BinaryOutputArchive.getArchive(baos);
                boa.writeRecord(hdr, null);
                boa.writeRecord(new CreateSessionTxn(30000), null);
                qp.setData(baos.toByteArray());
                oa.writeRecord(qp, null);
                // NEWLEADER is queued after startForwarding.
                qp.setType(Leader.NEWLEADER);
                qp.setZxid(ZxidUtils.makeZxid(1, 0));
                qp.setData(null);
                oa.writeRecord(qp, null);
                readPacketSkippingPing(ia, qp);
                assertEquals(Leader.ACK, qp.getType());
                assertEquals(ZxidUtils.makeZxid(1, 0), qp.getZxid());
                System.out.println("REPRO-CR1: NEWLEADER ACK received");
                // The outstanding proposal gets its quorum: the leader forwards COMMIT
                // before the learner's UPTODATE is queued.
                qp.setType(Leader.COMMIT);
                qp.setZxid(zxid);
                qp.setData(null);
                oa.writeRecord(qp, null);
                qp.setType(Leader.UPTODATE);
                qp.setZxid(0);
                oa.writeRecord(qp, null);
                try {
                    readPacketSkippingPing(ia, qp);
                } catch (IOException e) {
                    System.out.println("REPRO-CR1: learner connection closed after COMMIT/UPTODATE: " + e);
                    // CR-2 probe: request-processor threads started by startupWithoutServing() after the learner gave up.
                    Thread.sleep(1500);
                    java.util.List<String> live = new java.util.ArrayList<>();
                    for (Thread t : Thread.getAllStackTraces().keySet()) {
                        String n = t.getName();
                        if (t.isAlive() && (n.startsWith("SyncThread") || n.startsWith("CommitProcessor")
                            || n.startsWith("FollowerRequestProcessor") || n.startsWith("RequestThrottler")
                            || n.startsWith("SessionTracker"))) {
                            live.add(n);
                        }
                    }
                    java.util.Collections.sort(live);
                    System.out.println("REPRO-CR2: learner zk state=" + f.fzk.getState() + "; live request-processor threads 1.5s after the learner exited: "
                                       + live.size() + " " + live);
                    throw new AssertionError("learner aborted synchronization after a COMMIT between NEWLEADER and UPTODATE", e);
                }
                System.out.println("REPRO-CR1: UPTODATE ACK type=" + qp.getType() + " zxid=0x" + Long.toHexString(qp.getZxid()));
                assertEquals(Leader.ACK, qp.getType());
                long start = System.currentTimeMillis();
                while (f.fzk.getLastProcessedZxid() != zxid && System.currentTimeMillis() - start < 2000) {
                    Thread.sleep(10);
                }
                System.out.println("REPRO-CR1: learner lastProcessedZxid=0x" + Long.toHexString(f.fzk.getLastProcessedZxid()));
                assertEquals(zxid, f.fzk.getLastProcessedZxid());
            }
        });
    }
}
