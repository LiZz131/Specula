/*
 * Specula reproduction scenario (harness-only, not part of the product).
 * Derived from the update's DIFFSyncConsistencyTest: same fixture (learners
 * fail right after reading UPTODATE), but the learners are NOT restarted.
 * Instead the old leader is stopped once it serves the DIFF-synchronized
 * transaction, and the two learners elect a new leader among themselves.
 * Model finding MC-2 predicts the new leader's in-memory database (the FLE
 * vote basis and the loaded leader database) omits the transaction, because
 * the learners failed while their ZooKeeperServer was INITIAL and
 * LearnerZooKeeperServer.shutdown skipped fastForwardDataBase.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.test.ClientBase.CONNECTION_TIMEOUT;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;
import java.util.Map;
import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.KeeperException;
import org.apache.zookeeper.PortAssignment;
import org.apache.zookeeper.ZooDefs.Ids;
import org.apache.zookeeper.ZooDefs.OpCode;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.data.Stat;
import org.apache.zookeeper.server.quorum.Leader.Proposal;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.ClientBase.CountdownWatcher;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

public class SpeculaInitialStateFailureReproTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private final MainThread[] mt = new MainThread[SERVER_COUNT];

    @Test
    @Timeout(value = 240)
    public void testCommittedTxnSurvivesLearnerFailureWithoutRestart() throws Exception {
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
                    return new DIFFSyncConsistencyTest.MockTestQPMain();
                }
            };
            mt[i].start();
        }
        for (int i = 0; i < SERVER_COUNT; i++) {
            assertTrue(ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[i], CONNECTION_TIMEOUT),
                    "waiting for server " + i + " being up");
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
        String path = "/zk" + leader;
        try {
            zk.create(path, "zk".getBytes(), Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT);
            fail("create " + path + " should have failed");
        } catch (KeeperException e) {
            // expected: no quorum
        }
        assertTrue(outstanding.size() > 0);
        Proposal p = null;
        for (Proposal proposal : outstanding.values()) {
            if (proposal.request.getHdr().getType() == OpCode.create) {
                p = proposal;
            }
        }
        assertNotNull(p, "leader has no create proposal");
        int waited = 0;
        while (!p.qvAcksetPairs.get(0).getAckset().contains((long) leader)) {
            if (waited > 2000) {
                fail("create not synced on the old leader");
            }
            Thread.sleep(100);
            waited += 100;
        }

        // Restart the learners with the UPTODATE failure injected.
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i == leader) {
                continue;
            }
            mt[i].start();
            int c = 0;
            while (mt[i].getQuorumPeer() == null) {
                if (++c > 100) {
                    fail("cannot start learner " + i);
                }
                Thread.sleep(100);
            }
            ((DIFFSyncConsistencyTest.CustomQuorumPeer) mt[i].getQuorumPeer()).setInjectError(true);
        }

        // The old leader serves the transaction: it was committed by a NEWLEADER quorum.
        Stat served = null;
        for (int c = 0; c < 200 && served == null; c++) {
            try {
                served = zk.exists(path, false);
            } catch (KeeperException.ConnectionLossException e) {
                // retry
            }
            if (served == null) {
                Thread.sleep(100);
            }
        }
        assertNotNull(served, "old leader should serve " + path + " after NEWLEADER quorum");
        System.out.println("SPECULA-REPRO: old leader " + leader + " serves " + path);

        // Stop only the old leader; the learners are NOT restarted (no reload from disk).
        zk.close();
        mt[leader].shutdown();
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                ((DIFFSyncConsistencyTest.CustomQuorumPeer) mt[i].getQuorumPeer()).setInjectError(false);
            }
        }
        // Wait for a leader elected among the two learners that stays in BROADCAST.
        int newLeader = -1;
        int stable = 0;
        for (int c = 0; c < 1200 && stable < 30; c++) {
            int cand = -1;
            for (int i = 0; i < SERVER_COUNT; i++) {
                QuorumPeer qp = i == leader ? null : mt[i].getQuorumPeer();
                if (qp != null && qp.leader != null && qp.getZabState() == QuorumPeer.ZabState.BROADCAST) {
                    cand = i;
                }
            }
            if (cand >= 0 && cand == newLeader) {
                stable++;
            } else {
                stable = 0;
                newLeader = cand;
            }
            Thread.sleep(100);
        }
        assertTrue(newLeader >= 0 && stable >= 30, "no stable new leader among the learners");
        QuorumPeer np = mt[newLeader].getQuorumPeer();
        long epoch = np.getCurrentEpoch();
        boolean leaderHas = np.getZkDb().getNode(path) != null;
        System.out.println("SPECULA-REPRO: new leader " + newLeader + " epoch " + epoch
                + " lastLoggedZxid 0x" + Long.toHexString(np.getLastLoggedZxid())
                + " in-memory has " + path + " = " + leaderHas);
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader && i != newLeader && mt[i].getQuorumPeer() != null) {
                System.out.println("SPECULA-REPRO: learner " + i + " in-memory has " + path + " = "
                        + (mt[i].getQuorumPeer().getZkDb().getNode(path) != null));
            }
        }
        // Client-visible check (retried; the quorum may still be settling).
        for (int attempt = 0; attempt < 6; attempt++) {
            for (int i = 0; i < SERVER_COUNT; i++) {
                if (i == leader) {
                    continue;
                }
                try {
                    if (!ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[i], 10_000)) {
                        continue;
                    }
                    CountdownWatcher w2 = new CountdownWatcher();
                    ZooKeeper zk2 = new ZooKeeper("127.0.0.1:" + clientPorts[i], CONNECTION_TIMEOUT, w2);
                    w2.waitForConnected(20_000);
                    Stat after = zk2.exists(path, false);
                    System.out.println("SPECULA-REPRO: client on server " + i + " exists(" + path + ") = " + after);
                    zk2.close();
                } catch (Exception e) {
                    System.out.println("SPECULA-REPRO: client check on server " + i + " attempt " + attempt + " failed: " + e);
                }
            }
            Thread.sleep(2000);
        }
        assertTrue(leaderHas, "Data inconsistency: committed " + path
                + " served by the old leader is missing from the new leader's database (server " + newLeader + ")");
    }

    private int findLeader() {
        for (int i = 0; i < mt.length; i++) {
            if (mt[i].main.quorumPeer.leader != null) {
                return i;
            }
        }
        return -1;
    }

    @AfterEach
    public void tearDown() throws Exception {
        for (MainThread m : mt) {
            if (m != null) {
                m.shutdown();
            }
        }
    }
}
