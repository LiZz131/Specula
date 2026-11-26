/*
 * Specular reproduction for finding MC-1 (case-002, update 2efbdfc).
 *
 * Claim: a learner sends the NEWLEADER ACK after only *enqueueing* the
 * DIFF-synced proposals to its SyncRequestProcessor (Learner.syncWithLeader
 * NEWLEADER case -> FollowerZooKeeperServer.logRequest), so the leader can
 * form its NEWLEADER quorum and serve its whole history while the
 * transferred transaction is durable only on the leader.  If the acking
 * learners crash in that window and the old leader is unavailable, the
 * next leader does not have a transaction clients already read.
 *
 * Trigger control (no change to system logic):
 *  - Level 1 timing assistance: a test-fixture ZKDatabase subclass holds the
 *    learners' FileTxnLog commit (flush + fsync) for at most FSYNC_HOLD_MS,
 *    emulating a slow disk.  Nothing else in the processing path changes.
 *  - Crash emulation: when the leader first serves the transaction, each
 *    learner's data directory is copied.  The copy holds exactly the bytes
 *    the process had handed to the OS, i.e. what survives a SIGKILL at that
 *    instant (FileTxnLog keeps un-committed txn bytes in its Java buffer).
 *    Later the learners are restarted from those crash images.
 * The test fails ("Data inconsistency detected") when the bug manifests.
 * If an implementation sent the NEWLEADER ACK only after the fsync, the
 * leader could not serve the transaction before the hold ends, the images
 * would contain it, and the test would pass.
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
import java.util.Set;
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
import org.apache.zookeeper.server.ZKDatabase;
import org.apache.zookeeper.server.persistence.FileTxnSnapLog;
import org.apache.zookeeper.server.quorum.Leader.Proposal;
import org.apache.zookeeper.test.ClientBase;
import org.apache.zookeeper.test.ClientBase.CountdownWatcher;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Timeout;

public class NewLeaderAckDurabilityReproTest extends QuorumPeerTestBase {

    private static final int SERVER_COUNT = 3;
    private static final long FSYNC_HOLD_MS = Long.getLong("repro.fsyncHoldMs", 15000);
    /** false = control run: learners are shut down normally instead of restarting from crash images. */
    private static final boolean RESTORE_IMAGES = Boolean.parseBoolean(System.getProperty("repro.restoreImages", "true"));
    /** sids whose txn-log commits are held while {@link #gate} is open. */
    static final Set<Long> HELD = ConcurrentHashMap.newKeySet();
    static volatile CountDownLatch gate = new CountDownLatch(0);
    static volatile long heldCommits = 0;

    private final MainThread[] mt = new MainThread[SERVER_COUNT];

    @Test
    @Timeout(value = 240)
    public void testCommittedTxnSurvivesLearnerCrashAfterNewLeaderAck() throws Exception {
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
                    return new HeldQPMain();
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

        // Same preparation as DIFFSyncConsistencyTest: give the leader an
        // uncommitted, locally fsynced transaction /zk<leader>.
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
            fail("create should not have been committed without followers");
        } catch (KeeperException e) {
            // expected
        }
        Proposal p = null;
        for (Proposal q : outstanding.values()) {
            if (q.request.getHdr().getType() == OpCode.create) {
                p = q;
            }
        }
        assertNotNull(p, "leader has no create proposal");
        long waited = 0;
        while (!p.qvAcksetPairs.get(0).getAckset().contains((long) leader)) {
            assertTrue(waited < 5000, "leader did not fsync its own proposal");
            Thread.sleep(100);
            waited += 100;
        }

        // Slow learner disks: hold the learners' txn-log commits (bounded).
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                HELD.add((long) i);
            }
        }
        gate = new CountDownLatch(1);
        final CountDownLatch thisGate = gate;
        Thread releaser = new Thread(() -> {
            try {
                Thread.sleep(FSYNC_HOLD_MS);
            } catch (InterruptedException e) {
                return;
            }
            thisGate.countDown();
        });
        releaser.setDaemon(true);
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                mt[i].start();
            }
        }
        releaser.start();
        long holdStart = System.currentTimeMillis();

        // The moment the leader serves the transaction, record learner crash images.
        Path[] images = new Path[SERVER_COUNT];
        boolean seen = false;
        for (int c = 0; c < 600 && !seen; c++) {
            try {
                Stat stat = zk.exists("/zk" + leader, false);
                if (stat != null) {
                    seen = true;
                    break;
                }
            } catch (KeeperException.ConnectionLossException e) {
                // leader re-election in progress
            }
            Thread.sleep(50);
        }
        assertTrue(seen, "leader never served /zk" + leader);
        long servedAt = System.currentTimeMillis() - holdStart;
        boolean gateStillHeld = thisGate.getCount() > 0;
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                images[i] = copyDir(mt[i].tmpDir.toPath().resolve("data"));
            }
        }
        LOG.info("REPRO served /zk{} at {} ms after learner restart; learner fsync gate still held: {}; held commits: {}",
                 leader, servedAt, gateStillHeld, heldCommits);
        System.out.println("REPRO-OBSERVATION restore_images=" + RESTORE_IMAGES + " hold_ms=" + FSYNC_HOLD_MS
                           + " served_ms=" + servedAt + " gate_held_at_serve=" + gateStillHeld
                           + " held_commits=" + heldCommits);

        // Learners crash (images above); the old leader becomes unavailable.
        thisGate.countDown();
        HELD.clear();
        for (int i = 0; i < SERVER_COUNT; i++) {
            mt[i].shutdown();
        }
        waitForOne(zk, States.CONNECTING);
        zk.close();
        for (int i = 0; i < SERVER_COUNT; i++) {
            if (i != leader) {
                if (RESTORE_IMAGES) {
                    restoreDir(images[i], mt[i].tmpDir.toPath().resolve("data"));
                }
                mt[i].start();
            }
        }
        int newLeader = -1;
        for (int c = 0; c < 300 && newLeader < 0; c++) {
            newLeader = findLeader();
            if (newLeader == leader) {
                newLeader = -1;
            }
            Thread.sleep(100);
        }
        assertNotEquals(-1, newLeader, "no new leader among restarted learners");
        ZooKeeper zk2 = new ZooKeeper("127.0.0.1:" + clientPorts[newLeader], CONNECTION_TIMEOUT, watch);
        watch.waitForConnected(CONNECTION_TIMEOUT);
        Stat val = zk2.exists("/zk" + leader, false);
        System.out.println("REPRO-OBSERVATION new_leader=" + newLeader + " has_/zk" + leader + "=" + (val != null));
        zk2.close();
        assertNotNull(val, "Data inconsistency detected! /zk" + leader
                           + " was served by the old leader but is missing at new leader " + newLeader);
    }

    private int findLeader() {
        for (int i = 0; i < mt.length; i++) {
            if (mt[i].main != null && mt[i].main.quorumPeer != null && mt[i].main.quorumPeer.leader != null) {
                return i;
            }
        }
        return -1;
    }

    private static Path copyDir(Path src) throws IOException {
        Path dst = Files.createTempDirectory("crash-image");
        try (Stream<Path> s = Files.walk(src)) {
            for (Path f : (Iterable<Path>) s::iterator) {
                Path t = dst.resolve(src.relativize(f).toString());
                if (Files.isDirectory(f)) {
                    Files.createDirectories(t);
                } else {
                    Files.copy(f, t, StandardCopyOption.REPLACE_EXISTING);
                }
            }
        }
        return dst;
    }

    private static void restoreDir(Path image, Path target) throws IOException {
        try (Stream<Path> s = Files.walk(target)) {
            s.sorted(Comparator.reverseOrder()).map(Path::toFile).forEach(File::delete);
        }
        Files.createDirectories(target);
        try (Stream<Path> s = Files.walk(image)) {
            for (Path f : (Iterable<Path>) s::iterator) {
                Path t = target.resolve(image.relativize(f).toString());
                if (Files.isDirectory(f)) {
                    Files.createDirectories(t);
                } else {
                    Files.copy(f, t, StandardCopyOption.REPLACE_EXISTING);
                }
            }
        }
    }

    @AfterEach
    public void tearDown() {
        gate.countDown();
        HELD.clear();
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

    /** Test fixture: delays the txn-log commit (flush + fsync) of held peers. */
    static class HeldZKDatabase extends ZKDatabase {
        private final QuorumPeer peer;

        HeldZKDatabase(FileTxnSnapLog snapLog, QuorumPeer peer) {
            super(snapLog);
            this.peer = peer;
        }

        @Override
        public void commit() throws IOException {
            if (HELD.contains(peer.getId())) {
                heldCommits++;
                try {
                    gate.await(FSYNC_HOLD_MS + 5000, TimeUnit.MILLISECONDS);
                } catch (InterruptedException e) {
                    Thread.currentThread().interrupt();
                }
            }
            super.commit();
        }
    }

    static class HeldQuorumPeer extends QuorumPeer {
        HeldQuorumPeer() throws SaslException {
        }

        @Override
        public void setZKDatabase(ZKDatabase database) {
            super.setZKDatabase(new HeldZKDatabase(getTxnFactory(), this));
        }
    }

    static class HeldQPMain extends TestQPMain {
        @Override
        protected QuorumPeer getQuorumPeer() throws SaslException {
            return new HeldQuorumPeer();
        }
    }
}
