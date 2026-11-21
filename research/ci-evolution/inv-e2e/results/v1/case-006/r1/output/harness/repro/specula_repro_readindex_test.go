package raft

import (
	"testing"

	pb "github.com/coreos/etcd/raft/raftpb"
)

// TestSpeculaReproStaleReadAfterContextReuse is the standalone reproduction for
// Specula finding MC-1 (update scenarios US3/US4). It uses only the in-tree
// test network and raft.Step; it needs no Specula instrumentation.
//
// Requirement (node.go:154-157, rawnode.go:258-261): a read state's index must
// cover every write that completed before the ReadIndex request was issued.
//
//  1. Node 1 leads term 1 and commits; a safe ReadIndex with context "ctx" is
//     released by node 2's heartbeat ack. Node 3's ack for that same heartbeat
//     round is delayed in the network.
//  2. Node 1 is partitioned. Nodes 2 and 3 elect node 2 (term 2), which
//     commits a new write. That write has completed.
//  3. The client asks the still-leader (term 1) node 1 for a new ReadIndex,
//     reusing "ctx" (the first request has already completed).
//  4. Node 3's delayed term-1 ack from step 1 is delivered to node 1.
//
// The test fails if node 1 then produces a read state for the second request
// whose index is below the commit index of the write that completed before
// that request was issued.
func TestSpeculaReproStaleReadAfterContextReuse(t *testing.T) {
	nt := newNetwork(nil, nil, nil)
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgHup})
	n1 := nt.peers[1].(*raft)
	n2 := nt.peers[2].(*raft)
	n3 := nt.peers[3].(*raft)
	if n1.state != StateLeader {
		t.Fatalf("node 1 state = %v, want leader", n1.state)
	}

	ctx := []byte("ctx")
	n1.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	var ack2, ack3 pb.Message
	for _, hb := range n1.readMessages() {
		if hb.Type != pb.MsgHeartbeat {
			continue
		}
		p := nt.peers[hb.To].(*raft)
		p.Step(hb)
		for _, m := range p.readMessages() {
			if m.Type != pb.MsgHeartbeatResp {
				continue
			}
			if hb.To == 2 {
				ack2 = m
			} else if hb.To == 3 {
				ack3 = m
			}
		}
	}
	if ack2.Type != pb.MsgHeartbeatResp || ack3.Type != pb.MsgHeartbeatResp {
		t.Fatalf("setup: missing heartbeat acks: %v %v", ack2, ack3)
	}
	n1.Step(ack2)
	n1.readMessages()
	if len(n1.readStates) != 1 {
		t.Fatalf("setup: first read not served: %v", n1.readStates)
	}
	n1.readStates = nil

	nt.isolate(1)
	nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgHup})
	if n2.state != StateLeader {
		t.Fatalf("setup: node 2 state = %v, want leader", n2.state)
	}
	nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgProp, Entries: []pb.Entry{{Data: []byte("w")}}})
	completed := n2.raftLog.committed
	if completed <= n1.raftLog.committed || n3.raftLog.committed != completed {
		t.Fatalf("setup: newer write not committed: n2=%d n3=%d n1=%d",
			completed, n3.raftLog.committed, n1.raftLog.committed)
	}
	if n1.state != StateLeader || n1.Term != 1 {
		t.Fatalf("setup: node 1 state=%v term=%d, want leader of term 1", n1.state, n1.Term)
	}

	n1.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	n1.readMessages() // heartbeats for the second request are lost (partition)
	n1.Step(ack3)     // delayed ack from the first request's heartbeat round
	n1.readMessages()

	t.Logf("node1 term=%d commit=%d readStates=%v; write completed at index %d (term %d leader node 2)",
		n1.Term, n1.raftLog.committed, n1.readStates, completed, n2.Term)
	for _, rs := range n1.readStates {
		if rs.Index < completed {
			t.Fatalf("stale ReadIndex: second request for ctx %q got read index %d, "+
				"but index %d was committed (by the term-%d leader) before the request was issued",
				rs.RequestCtx, rs.Index, completed, n2.Term)
		}
	}
}
