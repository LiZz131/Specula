/*
 * Specular reproduction for code-review finding CR-2 (case-002, update 2efbdfc).
 *
 * Claim: after the update, a learner that fails between NEWLEADER and
 * UPTODATE has already started its request processors with
 * zk.startupWithoutServing() (state INITIAL) and handed the DIFF proposals to
 * its SyncRequestProcessor.  Learner.shutdown -> ZooKeeperServer.shutdown
 * returns early because canShutdown() is false for INITIAL, so (a) the
 * processor threads of the abandoned server keep running, and (b) the data
 * tree is not fast-forwarded while the leaked SyncThread makes the proposals
 * durable: the peer's election vote (getLastLoggedZxid = data tree) is lower
 * than its durable transaction log.
 *
 * Trigger: the same failure injection the update's own DIFFSyncConsistencyTest
 * uses (SocketTimeoutException after reading UPTODATE, emulating a network
 * timeout), applied to one follower that must DIFF-sync a transaction.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.test.ClientBase.CONNECTION_TIMEOUT;
import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import java.io.IOException;
import java.net.SocketTimeoutException;
import java.util.concurrent.atomic.AtomicInteger;
import javax.security.sasl.SaslException;
import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.PortAssignment;
import org.apache.zookeeper.ZooDefs.Ids;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.ClientBase.CountdownWatcher;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

public class LearnerInitialStateLeakReproTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private final MainThread[] mt = new MainThread[SERVER_COUNT];

    @Test
    @Timeout(value = 180)
    public void testLearnerFailureAfterNewLeaderReleasesServer() throws Exception {
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
                    return new FailingQPMain();
                }
            };
            mt[i].start();
        }
        for (int i = 0; i < SERVER_COUNT; i++) {
            assertTrue(ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[i], CONNECTION_TIMEOUT));
        }
        int leader = -1;
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (mt[i].main.quorumPeer.leader != null) {
                leader = i;
            }
        }
        int victim = (leader + 1) % SERVER_COUNT;
        CountdownWatcher watch = new CountdownWatcher();
        ZooKeeper zk = new ZooKeeper("127.0.0.1:" + clientPorts[leader], CONNECTION_TIMEOUT, watch);
        watch.waitForConnected(CONNECTION_TIMEOUT);

        // The victim misses a committed write, so its next sync is a DIFF.
        mt[victim].shutdown();
        zk.create("/missed", "x".getBytes(), Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT);

        int before = countThreads("SyncThread:" + victim);
        FailingQuorumPeer.failuresLeft.set(3);   // fail three NEWLEADER..UPTODATE windows
        FailingQuorumPeer.failSid = victim;
        mt[victim].start();
        long t0 = System.currentTimeMillis();
        while (FailingQuorumPeer.failuresLeft.get() > 0 && System.currentTimeMillis() - t0 < 60_000) {
            Thread.sleep(50);
        }
        // Observe the abandoned-server state right after the last injected failure.
        Thread.sleep(500);
        QuorumPeer qp = mt[victim].getQuorumPeer();
        long treeZxid = qp.getZkDb().getDataTreeLastProcessedZxid();
        FileTxnSnapLog log = qp.getTxnFactory();
        long logZxid = log.getLastLoggedZxid();
        int syncThreads = countThreads("SyncThread:" + victim);
        int commitThreads = countThreads("CommitProcessor:" + victim);
        System.out.println("REPRO-OBSERVATION victim=" + victim + " failures_injected=3 sync_threads_before="
                           + before + " sync_threads_after=" + syncThreads + " commit_threads_after=" + commitThreads
                           + " data_tree_zxid=0x" + Long.toHexString(treeZxid) + " txnlog_last_zxid=0x"
                           + Long.toHexString(logZxid) + " peer_state=" + qp.getPeerState());
        zk.close();
        // Expected (no leak): at most the processors of the one live session remain,
        // and the abandoned session's durable log is reflected in the data tree.
        assertTrue(syncThreads <= 1, "leaked SyncThread instances of abandoned learner servers: " + syncThreads);
        assertTrue(commitThreads <= 1, "leaked CommitProcessor instances of abandoned learner servers: " + commitThreads);
        assertEquals(Long.toHexString(logZxid), Long.toHexString(treeZxid),
                     "data tree (election vote) lags the durable txn log");
    }

    private static int countThreads(String name) {
        int n = 0;
        for (Thread t : Thread.getAllStackTraces().keySet()) {
            if (t.isAlive() && t.getName().equals(name)) {
                n++;
            }
        }
        return n;
    }

    @AfterEach
    public void tearDown() {
        FailingQuorumPeer.failuresLeft.set(0);
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

    static class FailingQuorumPeer extends QuorumPeer {
        static final AtomicInteger failuresLeft = new AtomicInteger();
        static volatile long failSid = -1;

        FailingQuorumPeer() throws SaslException {
        }

        @Override
        protected Follower makeFollower(FileTxnSnapLog logFactory) throws IOException {
            return new Follower(this, new FollowerZooKeeperServer(logFactory, this, this.getZkDb())) {
                @Override
                void readPacket(QuorumPacket pp) throws IOException {
                    super.readPacket(pp);
                    if (pp.getType() == Leader.UPTODATE && getId() == failSid
                        && failuresLeft.getAndUpdate(v -> v > 0 ? v - 1 : 0) > 0) {
                        throw new SocketTimeoutException("injected timeout after UPTODATE");
                    }
                }
            };
        }
    }

    static class FailingQPMain extends TestQPMain {
        @Override
        protected QuorumPeer getQuorumPeer() throws SaslException {
            return new FailingQuorumPeer();
        }
    }
}
