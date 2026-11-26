/*
 * Specular reproduction for code-review finding CR-3 (case-002, update 2efbdfc).
 *
 * Claim: after the update the learner's SyncRequestProcessor (started at
 * NEWLEADER) can write the ACK of a DIFF-synced proposal before the learner
 * thread writes the NEWLEADER ACK.  LearnerHandler.run takes the first ACK
 * after NEWLEADER as the NEWLEADER ACK and Leader.waitForNewLeaderAck drops an
 * ACK whose zxid is not the NEWLEADER zxid without counting the learner, so a
 * new leader can miss its NEWLEADER quorum although every learner acked.
 *
 * Trigger: Level 1 timing assistance only.  A test-fixture Follower delays the
 * learner thread's NEWLEADER-ACK write (first epoch-zxid ACK of the session)
 * by ACK_DELAY_MS, emulating a descheduled learner thread; the system logic is
 * unchanged.  The test expects the new leader to establish the very next epoch.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.test.ClientBase.CONNECTION_TIMEOUT;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;
import java.io.IOException;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
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

public class NewLeaderAckOrderReproTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private static final long ACK_DELAY_MS = Long.getLong("repro.ackDelayMs", 1500);
    static final Set<Long> DELAY_ONCE = ConcurrentHashMap.newKeySet();
    private final MainThread[] mt = new MainThread[SERVER_COUNT];

    @Test
    @Timeout(value = 240)
    public void testNewLeaderEstablishesNextEpochWhenAllLearnersAck() throws Exception {
        final int[] clientPorts = new int[SERVER_COUNT];
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < SERVER_COUNT; i++) {
            clientPorts[i] = PortAssignment.unique();
            sb.append("server." + i + "=127.0.0.1:" + PortAssignment.unique() + ":" + PortAssignment.unique()
                      + ":participant;127.0.0.1:" + clientPorts[i] + "\n");
        }
        for (int i = 0; i < SERVER_COUNT; i++) {
            mt[i] = new MainThread(i, clientPorts[i], sb.toString(), false) {
                @Override
                public TestQPMain getTestQPMain() {
                    return new SlowAckQPMain();
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
        // Same preparation as DIFFSyncConsistencyTest: the leader alone logs /zk<leader>,
        // so both learners receive a DIFF proposal when they rejoin.
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
            fail("create should not commit");
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
        long w = 0;
        while (!p.qvAcksetPairs.get(0).getAckset().contains((long) leader)) {
            assertTrue(w < 5000);
            Thread.sleep(100);
            w += 100;
        }
        long epochBefore = mt[leader].main.quorumPeer.getAcceptedEpoch();
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                DELAY_ONCE.add((long) i);
                mt[i].start();
            }
        }
        long restartAt = System.currentTimeMillis();
        boolean seen = false;
        for (int c = 0; c < 2400 && !seen; c++) {
            try {
                seen = zk.exists("/zk" + leader, false) != null;
            } catch (KeeperException.ConnectionLossException e) {
                // election in progress
            }
            Thread.sleep(50);
        }
        assertTrue(seen, "ensemble never served /zk" + leader);
        long servedMs = System.currentTimeMillis() - restartAt;
        int established = findLeader();
        long epochAfter = mt[established].main.quorumPeer.getCurrentEpoch();
        System.out.println("REPRO-OBSERVATION ack_delay_ms=" + ACK_DELAY_MS + " leader_before=" + leader
                           + " epoch_before=" + epochBefore + " leader_after=" + established
                           + " established_epoch=" + epochAfter + " served_ms_after_learner_restart=" + servedMs);
        zk.close();
        assertEquals(epochBefore + 1, epochAfter,
                     "NEWLEADER quorum was missed: an extra leader election/epoch was needed although all learners acked");
        // Every learner sends its NEWLEADER ACK within ~ACK_DELAY_MS of syncing; the leader
        // should then activate without waiting for a learner sync timeout and re-sync.
        assertTrue(servedMs < 10_000 + ACK_DELAY_MS,
                   "NEWLEADER quorum was missed: leader activation took " + servedMs
                   + " ms although all learners acked NEWLEADER (acks dropped until learner re-sync)");
    }

    private int findLeader() {
        for (int i = 0; i < mt.length; i++) {
            if (mt[i].main != null && mt[i].main.quorumPeer != null && mt[i].main.quorumPeer.leader != null) {
                return i;
            }
        }
        return -1;
    }

    @AfterEach
    public void tearDown() {
        DELAY_ONCE.clear();
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

    static class SlowAckQuorumPeer extends QuorumPeer {
        SlowAckQuorumPeer() throws SaslException {
        }

        @Override
        protected Follower makeFollower(FileTxnSnapLog logFactory) throws IOException {
            final long sid = getId();
            return new Follower(this, new FollowerZooKeeperServer(logFactory, this, this.getZkDb())) {
                @Override
                void writePacket(QuorumPacket pp, boolean flush) throws IOException {
                    if (pp != null && pp.getType() == Leader.ACK && (pp.getZxid() & 0xffffffffL) == 0
                        && Thread.currentThread() instanceof QuorumPeer && DELAY_ONCE.remove(sid)) {
                        try {
                            Thread.sleep(ACK_DELAY_MS);   // learner thread descheduled before the NEWLEADER ACK
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                    }
                    super.writePacket(pp, flush);
                }
            };
        }
    }

    static class SlowAckQPMain extends TestQPMain {
        @Override
        protected QuorumPeer getQuorumPeer() throws SaslException {
            return new SlowAckQuorumPeer();
        }
    }
}
