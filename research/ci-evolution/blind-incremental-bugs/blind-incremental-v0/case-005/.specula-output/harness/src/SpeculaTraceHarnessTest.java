package org.apache.zookeeper.server.quorum;

import java.nio.charset.StandardCharsets;

import org.apache.zookeeper.CreateMode;
import org.apache.zookeeper.PortAssignment;
import org.apache.zookeeper.ZooDefs.Ids;
import org.apache.zookeeper.ZooKeeper;
import org.apache.zookeeper.ZooKeeper.States;
import org.apache.zookeeper.test.ClientBase;
import org.junit.Assert;
import org.junit.Test;

/**
 * Neutral trace scenario for the Specula prior. It exercises ordinary cluster
 * startup, committed mutations, follower catch-up, clean shutdown, and durable
 * recovery without targeting a previously identified failure.
 */
public class SpeculaTraceHarnessTest extends QuorumPeerTestBase {
    private static final int SERVER_COUNT = 3;

    @Test(timeout = 180000)
    public void testStartupMutationFollowerRestartAndRecovery() throws Exception {
        ClientBase.setupTestEnv();
        int[] clientPorts = new int[SERVER_COUNT];
        StringBuilder config = new StringBuilder();
        for (int i = 0; i < SERVER_COUNT; i++) {
            clientPorts[i] = PortAssignment.unique();
            config.append("server.").append(i).append("=127.0.0.1:")
                    .append(PortAssignment.unique()).append(":")
                    .append(PortAssignment.unique()).append(";")
                    .append(clientPorts[i]).append("\n");
        }

        MainThread[] peers = new MainThread[SERVER_COUNT];
        ZooKeeper client = null;
        ZooKeeper recoveredClient = null;
        ZooKeeper restartedClient = null;
        try {
            for (int i = 0; i < SERVER_COUNT; i++) {
                peers[i] = new MainThread(i, clientPorts[i], config.toString());
                peers[i].start();
            }
            waitUp(clientPorts);

            client = new ZooKeeper(connectString(clientPorts),
                    ClientBase.CONNECTION_TIMEOUT, this);
            waitConnected(client);
            client.create("/specula-a", bytes("one"), Ids.OPEN_ACL_UNSAFE,
                    CreateMode.PERSISTENT);

            int follower = findFollower(peers);
            Assert.assertTrue("an elected follower is required", follower >= 0);
            peers[follower].shutdown();
            Assert.assertTrue("follower stopped",
                    ClientBase.waitForServerDown("127.0.0.1:" + clientPorts[follower],
                            ClientBase.CONNECTION_TIMEOUT));

            client.create("/specula-b", bytes("two"), Ids.OPEN_ACL_UNSAFE,
                    CreateMode.PERSISTENT);
            client.setData("/specula-a", bytes("three"), -1);

            peers[follower].start();
            Assert.assertTrue("restarted follower became available",
                    ClientBase.waitForServerUp("127.0.0.1:" + clientPorts[follower],
                            ClientBase.CONNECTION_TIMEOUT));
            recoveredClient = new ZooKeeper("127.0.0.1:" + clientPorts[follower],
                    ClientBase.CONNECTION_TIMEOUT, this);
            waitConnected(recoveredClient);
            Assert.assertArrayEquals(bytes("two"),
                    recoveredClient.getData("/specula-b", false, null));
            Assert.assertArrayEquals(bytes("three"),
                    recoveredClient.getData("/specula-a", false, null));

            recoveredClient.close();
            recoveredClient = null;
            client.close();
            client = null;
            shutdownAll(peers);
            waitDown(clientPorts);

            for (MainThread peer : peers) {
                peer.start();
            }
            waitUp(clientPorts);
            restartedClient = new ZooKeeper(connectString(clientPorts),
                    ClientBase.CONNECTION_TIMEOUT, this);
            waitConnected(restartedClient);
            Assert.assertArrayEquals(bytes("two"),
                    restartedClient.getData("/specula-b", false, null));
            restartedClient.create("/specula-c", bytes("four"),
                    Ids.OPEN_ACL_UNSAFE, CreateMode.PERSISTENT);
        } finally {
            closeQuietly(restartedClient);
            closeQuietly(recoveredClient);
            closeQuietly(client);
            shutdownAll(peers);
        }
    }

    private static byte[] bytes(String value) {
        return value.getBytes(StandardCharsets.UTF_8);
    }

    private static String connectString(int[] ports) {
        StringBuilder result = new StringBuilder();
        for (int port : ports) {
            if (result.length() > 0) {
                result.append(',');
            }
            result.append("127.0.0.1:").append(port);
        }
        return result.toString();
    }

    private static void waitConnected(ZooKeeper client) throws Exception {
        long deadline = System.currentTimeMillis() + ClientBase.CONNECTION_TIMEOUT;
        while (client.getState() != States.CONNECTED
                && System.currentTimeMillis() < deadline) {
            Thread.sleep(50);
        }
        Assert.assertEquals("client connected", States.CONNECTED, client.getState());
    }

    private static void waitUp(int[] ports) throws Exception {
        for (int port : ports) {
            Assert.assertTrue("server became available",
                    ClientBase.waitForServerUp("127.0.0.1:" + port,
                            ClientBase.CONNECTION_TIMEOUT));
        }
    }

    private static void waitDown(int[] ports) throws Exception {
        for (int port : ports) {
            Assert.assertTrue("server stopped",
                    ClientBase.waitForServerDown("127.0.0.1:" + port,
                            ClientBase.CONNECTION_TIMEOUT));
        }
    }

    private static int findFollower(MainThread[] peers) {
        for (int i = 0; i < peers.length; i++) {
            QuorumPeer peer = peers[i].main.quorumPeer;
            if (peer != null && peer.follower != null && peer.leader == null) {
                return i;
            }
        }
        return -1;
    }

    private static void shutdownAll(MainThread[] peers) throws Exception {
        for (MainThread peer : peers) {
            if (peer != null) {
                peer.shutdown();
            }
        }
    }

    private static void closeQuietly(ZooKeeper client) {
        if (client != null) {
            try {
                client.close();
            } catch (InterruptedException ignored) {
                Thread.currentThread().interrupt();
            }
        }
    }
}
