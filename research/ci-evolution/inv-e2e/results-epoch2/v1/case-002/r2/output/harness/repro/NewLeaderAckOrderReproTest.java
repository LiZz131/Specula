/*
 * Specular code-review candidate CR-3 (case-002, run incr-8c80add29fe2).
 * Claim: the update starts SyncRequestProcessor/SendAckRequestProcessor at NEWLEADER
 * (Learner.java:751-756) before the learner thread writes the NEWLEADER ACK
 * (:760).  If SyncThread flushes a handed-off txn first, its per-txn ACK is the
 * first ACK LearnerHandler reads after NEWLEADER (LearnerHandler.java:611-623);
 * Leader.waitForNewLeaderAck rejects its zxid as "from a different epoch"
 * (Leader.java:1555-1563) and the real NEWLEADER ACK is later ignored by
 * processAck (counter 0), so that learner never counts toward the NEWLEADER quorum.
 * Level 1 timing assistance: the learner thread is descheduled (sleep) for
 * ACK_DELAY_MS right before writing the NEWLEADER ACK; no logic is changed.
 */
package org.apache.zookeeper.server.quorum;

import static org.apache.zookeeper.test.ClientBase.CONNECTION_TIMEOUT;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.junit.jupiter.api.Assertions.fail;
import java.io.File;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardCopyOption;
import java.util.Comparator;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.stream.Stream;
import javax.security.sasl.SaslException;
import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.KeeperException;
import org.apache.zookeeper.PortAssignment;
import org.apache.zookeeper.ZooDefs.Ids;
import org.apache.zookeeper.ZooDefs.OpCode;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.ZooKeeper.States;
import org.apache.zookeeper.data.Stat;
import org.apache.zookeeper.server.Request;
import org.apache.zookeeper.server.ZKDatabase;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.server.quorum.Leader.Proposal;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.ClientBase.CountdownWatcher;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

public class NewLeaderAckOrderReproTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private final MainThread[] mt = new MainThread[SERVER_COUNT];

    /** Per-server controls; only armed followers are affected. */
    static final class Probe {
        volatile boolean armed;
        volatile long targetZxid = -1;
        volatile long slowAppendMs = 0;
        volatile long lastAppended = -1;
        volatile long durableUpTo = -1;
        volatile File dataDir;
        volatile File crashImage;
        volatile Boolean durableAtAck;
        final CountDownLatch captured = new CountDownLatch(1);
    }

    static final Map<Long, Probe> PROBES = new ConcurrentHashMap<>();

    static Probe probe(long sid) {
        return PROBES.computeIfAbsent(sid, k -> new Probe());
    }

    /** Slow transaction-log device: delays append; tracks what commit() forced. */
    static final class SlowZKDatabase extends ZKDatabase {
        private final long sid;

        SlowZKDatabase(FileTxnSnapLog snapLog, long sid) {
            super(snapLog);
            this.sid = sid;
        }

        @Override
        public boolean append(Request si) throws IOException {
            Probe p = probe(sid);
            if (p.armed && si.getHdr() != null) {
                try {
                    Thread.sleep(p.slowAppendMs);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            boolean r = super.append(si);
            if (r && si.getHdr() != null) {
                p.lastAppended = Math.max(p.lastAppended, si.getHdr().getZxid());
            }
            return r;
        }

        @Override
        public void commit() throws IOException {
            super.commit();
            Probe p = probe(sid);
            p.durableUpTo = Math.max(p.durableUpTo, p.lastAppended);
        }
    }

    static class CustomQuorumPeer extends QuorumPeer {
        CustomQuorumPeer() throws SaslException {
        }

        @Override
        public void setZKDatabase(ZKDatabase database) {
            super.setZKDatabase(new SlowZKDatabase(getTxnFactory(), getId()));
        }

        @Override
        protected Follower makeFollower(FileTxnSnapLog logFactory) throws IOException {
            final QuorumPeer self = this;
            return new Follower(this, new FollowerZooKeeperServer(logFactory, this, this.getZkDb())) {
                @Override
                void writePacket(QuorumPacket pp, boolean flush) throws IOException {
                    Probe p = probe(self.getId());
                    if (p.armed && p.crashImage == null && pp.getType() == Leader.ACK
                        && (pp.getZxid() & 0xffffffffL) == 0) {
                        p.crashImage = new File("/dev/null");
                        try {
                            Thread.sleep(Long.parseLong(System.getenv().getOrDefault("REPRO_ACK_DELAY_MS", "500")));
                        } catch (InterruptedException e) {
                            Thread.currentThread().interrupt();
                        }
                        System.out.println("REPRO-CR3: server " + self.getId() + " writes NEWLEADER ACK 0x"
                                           + Long.toHexString(pp.getZxid()) + " after txn ACKs up to 0x"
                                           + Long.toHexString(p.durableUpTo));
                        p.durableAtAck = p.durableUpTo >= p.targetZxid;
                        p.captured.countDown();
                    }
                    super.writePacket(pp, flush);
                }
            };
        }
    }

    static class MockTestQPMain extends TestQPMain {
        @Override
        protected QuorumPeer getQuorumPeer() throws SaslException {
            return new CustomQuorumPeer();
        }
    }

    static File snapshotDir(File dir, long sid) throws IOException {
        Path dst = Files.createTempDirectory("repro-crash-image-" + sid + "-");
        Path src = dir.toPath();
        try (Stream<Path> s = Files.walk(src)) {
            for (Path p : (Iterable<Path>) s::iterator) {
                Path t = dst.resolve(src.relativize(p).toString());
                if (Files.isDirectory(p)) {
                    Files.createDirectories(t);
                } else {
                    Files.copy(p, t, StandardCopyOption.REPLACE_EXISTING);
                }
            }
        }
        return dst.toFile();
    }

    static void restoreDir(File image, File dir) throws IOException {
        try (Stream<Path> s = Files.walk(dir.toPath())) {
            s.sorted(Comparator.reverseOrder()).filter(p -> !p.equals(dir.toPath())).forEach(p -> p.toFile().delete());
        }
        Path src = image.toPath();
        try (Stream<Path> s = Files.walk(src)) {
            for (Path p : (Iterable<Path>) s::iterator) {
                Path t = dir.toPath().resolve(src.relativize(p).toString());
                if (Files.isDirectory(p)) {
                    Files.createDirectories(t);
                } else {
                    Files.copy(p, t, StandardCopyOption.REPLACE_EXISTING);
                }
            }
        }
    }

    @Test
    @Timeout(value = 240)
    public void testNewLeaderAckNotOvertakenByTxnAck() throws Exception {
        PROBES.clear();
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
                    return new MockTestQPMain();
                }
            };
            mt[i].start();
        }
        for (int i = 0; i < SERVER_COUNT; i++) {
            assertTrue(ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[i], CONNECTION_TIMEOUT));
        }
        int leader = findLeader(mt);
        CountdownWatcher watch = new CountdownWatcher();
        ZooKeeper zk = new ZooKeeper("127.0.0.1:" + clientPorts[leader], CONNECTION_TIMEOUT, watch);
        watch.waitForConnected(CONNECTION_TIMEOUT);

        // Same setup as the update's DIFFSyncConsistencyTest: the leader logs a
        // proposal while both followers are down, so they receive it by DIFF.
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
            fail("create /zk" + leader + " should not complete without a quorum");
        } catch (KeeperException e) {
            // expected: no quorum
        }
        Proposal p = null;
        for (Proposal x : outstanding.values()) {
            if (x.request.getHdr().getType() == OpCode.create) {
                p = x;
            }
        }
        assertNotNull(p, "leader has no create proposal");
        long target = p.request.zxid;
        int waited = 0;
        while (!p.qvAcksetPairs.get(0).getAckset().contains((long) leader)) {
            assertTrue(waited < 5000, "leader did not log the proposal");
            Thread.sleep(100);
            waited += 100;
        }
        System.out.println("REPRO: leader " + leader + " logged /zk" + leader + " as txn 0x" + Long.toHexString(target));

        // Restart the followers with a slow log device and the ACK-instant crash probe.
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i == leader) {
                continue;
            }
            Probe pr = probe(i);
            pr.targetZxid = target;
            pr.dataDir = new File(mt[i].tmpDir, "data");
            pr.armed = true;
            mt[i].start();
        }
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                assertTrue(probe(i).captured.await(60, TimeUnit.SECONDS), "follower " + i + " never acked NEWLEADER");
            }
        }

        // Expected: the leader forms its NEWLEADER quorum and serves promptly.
        long t0 = System.currentTimeMillis();
        boolean served = false;
        while (!served && System.currentTimeMillis() - t0 < 15_000) {
            try {
                served = zk.exists("/zk" + leader, false) != null;
            } catch (KeeperException.ConnectionLossException e) {
                Thread.sleep(100);
            }
        }
        System.out.println("REPRO-CR3: leader served /zk" + leader + " within 15s after both NEWLEADER ACKs: " + served
                           + " (txn durable before NEWLEADER ACK: " + probe((leader + 1) % 3).durableAtAck + ", "
                           + probe((leader + 2) % 3).durableAtAck + ")");
        zk.close();
        assertTrue(served, "leader did not start serving within 15s although both followers sent NEWLEADER ACK");
    }

    @AfterEach
    public void tearDown() {
        for (int i = 0; i < mt.length; i++) {
            try {
                if (mt[i] != null) {
                    mt[i].shutdown();
                }
            } catch (InterruptedException e) {
                LOG.warn("interrupted", e);
            }
        }
        PROBES.clear();
    }

    private int findLeader(MainThread[] mt) {
        for (int i = 0; i < mt.length; i++) {
            if (mt[i].main.quorumPeer.leader != null) {
                return i;
            }
        }
        return -1;
    }
}
