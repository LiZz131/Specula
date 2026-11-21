package raft

import (
	"os"
	"testing"

	pb "github.com/coreos/etcd/raft/raftpb"
)

// TestSpeculaTraceQuorumRead drives the exact-old state machine and its real
// in-tree message-routing test network. The core instrumentation emits NDJSON;
// this test does not synthesize protocol states or trace lines.
func TestSpeculaTraceQuorumRead(t *testing.T) {
	path := os.Getenv("SPECULA_TRACE_PATH")
	if path == "" {
		t.Skip("SPECULA_TRACE_PATH is not set")
	}

	nt := newNetwork(nil, nil, nil)
	if err := speculaTraceStart(path); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := speculaTraceStop(); err != nil {
			t.Error(err)
		}
	}()

	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgHup})
	lead := nt.peers[1].(*raft)
	if lead.state != StateLeader {
		t.Fatalf("node 1 state = %v, want leader", lead.state)
	}

	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgProp,
		Entries: []pb.Entry{{Data: []byte("v1")}}})
	if lead.raftLog.committed < 2 {
		t.Fatalf("commit = %d, want at least 2", lead.raftLog.committed)
	}

	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	if len(lead.readStates) != 1 {
		t.Fatalf("read states = %d, want 1", len(lead.readStates))
	}

	_ = newReady(lead, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}

// TestSpeculaTraceQuorumLoss records the heartbeat-activity reset followed by
// exact-old leader step-down when the next quorum check sees no active peers.
func TestSpeculaTraceQuorumLoss(t *testing.T) {
	path := os.Getenv("SPECULA_TRACE_PATH")
	if path == "" {
		t.Skip("SPECULA_TRACE_PATH is not set")
	}

	nt := newNetwork(nil, nil, nil)
	if err := speculaTraceStart(path); err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := speculaTraceStop(); err != nil {
			t.Error(err)
		}
	}()

	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgHup})
	lead := nt.peers[1].(*raft)
	if lead.state != StateLeader {
		t.Fatalf("node 1 state = %v, want leader", lead.state)
	}

	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgCheckQuorum})
	if lead.state != StateLeader {
		t.Fatalf("first quorum check state = %v, want leader", lead.state)
	}
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgCheckQuorum})
	if lead.state != StateFollower {
		t.Fatalf("second quorum check state = %v, want follower", lead.state)
	}
}
