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

// ---------------------------------------------------------------------------
// Update-focused scenarios (incremental revision c780d355). All protocol
// states and messages come from the real raft state machine; the tests only
// choose message delivery order through the in-tree network or raw Step.
// ---------------------------------------------------------------------------

func speculaTraceBegin(t *testing.T) func() {
	path := os.Getenv("SPECULA_TRACE_PATH")
	if path == "" {
		t.Skip("SPECULA_TRACE_PATH is not set")
	}
	if err := speculaTraceStart(path); err != nil {
		t.Fatal(err)
	}
	return func() {
		if err := speculaTraceStop(); err != nil {
			t.Error(err)
		}
	}
}

func speculaElectAndCommit(t *testing.T, nt *network) *raft {
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
	return lead
}

// TestSpeculaTraceReadReuse (Scenario U1/U2, normal delivery): a safe read
// for ctx1 completes and its pending entry is freed; a second request with
// the same caller context is registered again and completes.
func TestSpeculaTraceReadReuse(t *testing.T) {
	defer speculaTraceBegin(t)()
	nt := newNetwork(nil, nil, nil)
	lead := speculaElectAndCommit(t, nt)

	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	if len(lead.readStates) != 1 {
		t.Fatalf("read states = %d, want 1", len(lead.readStates))
	}
	if len(lead.readOnly.pendingReadIndex) != 0 || len(lead.readOnly.readIndexQueue) != 0 {
		t.Fatalf("pending=%d queue=%d after release, want 0/0",
			len(lead.readOnly.pendingReadIndex), len(lead.readOnly.readIndexQueue))
	}
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	if len(lead.readStates) != 2 {
		t.Fatalf("read states after reuse = %d, want 2", len(lead.readStates))
	}
	_ = newReady(lead, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}

// TestSpeculaTraceForwardedRead (Scenario U4): follower 2 forwards ctx1, the
// leader releases it as MsgReadIndexResp and frees it; follower 3 then
// forwards the same caller context, which is registered again.
func TestSpeculaTraceForwardedRead(t *testing.T) {
	defer speculaTraceBegin(t)()
	nt := newNetwork(nil, nil, nil)
	lead := speculaElectAndCommit(t, nt)
	f2 := nt.peers[2].(*raft)
	f3 := nt.peers[3].(*raft)

	nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	if len(f2.readStates) != 1 {
		t.Fatalf("follower 2 read states = %d, want 1", len(f2.readStates))
	}
	if len(lead.readOnly.pendingReadIndex) != 0 {
		t.Fatalf("leader pending = %d after forwarded release, want 0",
			len(lead.readOnly.pendingReadIndex))
	}
	nt.send(pb.Message{From: 3, To: 3, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	if len(f3.readStates) != 1 {
		t.Fatalf("follower 3 read states = %d, want 1", len(f3.readStates))
	}
}

// TestSpeculaTraceStepDownWithPending (repair R1): the leader registers a
// read whose heartbeats are lost, then steps down on CheckQuorum; reset()
// recreates readOnly.
func TestSpeculaTraceStepDownWithPending(t *testing.T) {
	defer speculaTraceBegin(t)()
	nt := newNetwork(nil, nil, nil)
	lead := speculaElectAndCommit(t, nt)
	nt.isolate(1)
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	if len(lead.readOnly.pendingReadIndex) != 1 {
		t.Fatalf("pending = %d, want 1", len(lead.readOnly.pendingReadIndex))
	}
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgCheckQuorum})
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgCheckQuorum})
	if lead.state != StateFollower {
		t.Fatalf("state = %v, want follower", lead.state)
	}
	if len(lead.readOnly.pendingReadIndex) != 0 || len(lead.readOnly.readIndexQueue) != 0 {
		t.Fatalf("read-only state not recreated on step-down")
	}
}

// TestSpeculaTraceStaleAckReuse (Scenarios U2/U3 interaction): node 2's
// heartbeat response for the first ctx1 request is delayed; nodes 2 and 3
// elect node 2 in term 2 and commit; node 1 (still leader of term 1) gets a
// second ctx1 request and then the delayed term-1 response. Only raw
// raft.Step calls and the in-tree network are used.
func TestSpeculaTraceStaleAckReuse(t *testing.T) {
	defer speculaTraceBegin(t)()
	nt := newNetwork(nil, nil, nil)
	lead := speculaElectAndCommit(t, nt)
	n2 := nt.peers[2].(*raft)
	n3 := nt.peers[3].(*raft)
	ctx := []byte("ctx1")

	// Round 1: register ctx1 and deliver heartbeats by hand.
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	var delayed []pb.Message
	for _, hb := range lead.readMessages() {
		switch hb.To {
		case 2:
			n2.Step(hb)
			delayed = n2.readMessages() // held in the network
		case 3:
			n3.Step(hb)
			for _, resp := range n3.readMessages() {
				lead.Step(resp)
			}
		}
	}
	lead.readMessages()
	if len(lead.readStates) != 1 || len(delayed) != 1 || delayed[0].Type != pb.MsgHeartbeatResp {
		t.Fatalf("round 1: readStates=%d delayed=%v", len(lead.readStates), delayed)
	}

	// Nodes 2 and 3 elect node 2 in term 2 and commit its entry; node 1 is cut off.
	nt.isolate(1)
	nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgHup})
	if n2.state != StateLeader || n2.raftLog.committed <= lead.raftLog.committed {
		t.Fatalf("node 2 state=%v committed=%d, want leader with commit > %d",
			n2.state, n2.raftLog.committed, lead.raftLog.committed)
	}

	// Round 2 at the old leader: the same caller context is registered again
	// and the delayed term-1 response arrives.
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	lead.readMessages() // round-2 heartbeats are not delivered
	lead.Step(delayed[0])
	t.Logf("old leader term=%d state=%v readStates=%+v; new leader term=%d committed=%d",
		lead.Term, lead.state, lead.readStates, n2.Term, n2.raftLog.committed)
	// Publish both ReadStates at the Ready boundary (node.go:521-523).
	_ = newReady(lead, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}
