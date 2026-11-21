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

// speculaRelay delivers one message to its destination peer and returns the
// messages that peer produced. It is a manual, single-message version of the
// in-tree network.send used to hold or drop individual messages.
func speculaRelay(t *testing.T, nt *network, m pb.Message) []pb.Message {
	p, ok := nt.peers[m.To].(*raft)
	if !ok {
		t.Fatalf("peer %d is not a *raft", m.To)
	}
	if err := p.Step(m); err != nil {
		t.Fatal(err)
	}
	return p.readMessages()
}

func speculaPickResp(t *testing.T, msgs []pb.Message, typ pb.MessageType) pb.Message {
	for _, m := range msgs {
		if m.Type == typ {
			return m
		}
	}
	t.Fatalf("no %v among %v", typ, msgs)
	return pb.Message{}
}

func speculaObserve(t *testing.T, label string, r *raft) {
	t.Logf("OBSERVE %s node=%d term=%d state=%v commit=%d queue=%v pending=%d readStates=%v",
		label, r.id, r.Term, r.state, r.raftLog.committed, r.readOnly.readIndexQueue,
		len(r.readOnly.pendingReadIndex), r.readStates)
}

// TestSpeculaTraceReadReuse (update scenarios US1, US2, US3, US6).
// A forwarded read (ctx2) completes through the in-tree network; then a local
// read (ctx1) is released by node 2's ack while node 3's ack is held, the same
// context is requested again, and the held ack from the first heartbeat round
// is delivered.
func TestSpeculaTraceReadReuse(t *testing.T) {
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
	n2 := nt.peers[2].(*raft)
	if lead.state != StateLeader {
		t.Fatalf("node 1 state = %v, want leader", lead.state)
	}

	// US6: follower-forwarded read through the real network.
	nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx2")}}})
	speculaObserve(t, "after-forwarded-read-leader", lead)
	speculaObserve(t, "after-forwarded-read-follower", n2)

	// US1: first local read of ctx1; hold node 3's acknowledgement.
	ctx := []byte("ctx1")
	if err := lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: ctx}}}); err != nil {
		t.Fatal(err)
	}
	var resp2, resp3 pb.Message
	for _, hb := range lead.readMessages() {
		out := speculaRelay(t, nt, hb)
		r := speculaPickResp(t, out, pb.MsgHeartbeatResp)
		if hb.To == 2 {
			resp2 = r
		} else {
			resp3 = r
		}
	}
	if err := lead.Step(resp2); err != nil {
		t.Fatal(err)
	}
	_ = lead.readMessages()
	speculaObserve(t, "after-first-release", lead)

	// US2: the same context is requested again; its heartbeats are lost.
	if err := lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: ctx}}}); err != nil {
		t.Fatal(err)
	}
	_ = lead.readMessages()
	speculaObserve(t, "after-reenqueue", lead)

	// US3: the held acknowledgement from the first heartbeat round arrives.
	if err := lead.Step(resp3); err != nil {
		t.Fatal(err)
	}
	_ = lead.readMessages()
	speculaObserve(t, "after-delayed-ack", lead)

	_ = newReady(lead, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
	_ = newReady(n2, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}

// TestSpeculaTraceStaleRead (update scenario US4). As in ReadReuse, but
// before the context is reused the old leader is partitioned and nodes 2 and 3
// elect node 2, which commits a new entry. The old leader still leads term 1.
func TestSpeculaTraceStaleRead(t *testing.T) {
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
	n2 := nt.peers[2].(*raft)
	if lead.state != StateLeader {
		t.Fatalf("node 1 state = %v, want leader", lead.state)
	}

	ctx := []byte("ctx1")
	if err := lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: ctx}}}); err != nil {
		t.Fatal(err)
	}
	var resp2, resp3 pb.Message
	for _, hb := range lead.readMessages() {
		out := speculaRelay(t, nt, hb)
		r := speculaPickResp(t, out, pb.MsgHeartbeatResp)
		if hb.To == 2 {
			resp2 = r
		} else {
			resp3 = r
		}
	}
	if err := lead.Step(resp2); err != nil {
		t.Fatal(err)
	}
	_ = lead.readMessages()
	speculaObserve(t, "after-first-release", lead)

	nt.isolate(1)
	nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgHup})
	if n2.state != StateLeader {
		t.Fatalf("node 2 state = %v, want leader", n2.state)
	}
	nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgProp,
		Entries: []pb.Entry{{Data: []byte("v1")}}})
	speculaObserve(t, "newer-leader", n2)

	if err := lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: ctx}}}); err != nil {
		t.Fatal(err)
	}
	_ = lead.readMessages()
	speculaObserve(t, "after-reenqueue", lead)
	if err := lead.Step(resp3); err != nil {
		t.Fatal(err)
	}
	_ = lead.readMessages()
	speculaObserve(t, "after-delayed-ack", lead)
	t.Logf("OBSERVE newer-leader-commit=%d old-leader-readStates=%v",
		n2.raftLog.committed, lead.readStates)

	_ = newReady(lead, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}

// TestSpeculaTraceReadStepDown (update scenario US5): a pending read is
// discarded by the CheckQuorum step-down reset; after re-election the same
// context is accepted and served normally.
func TestSpeculaTraceReadStepDown(t *testing.T) {
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
	nt.isolate(1)
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	speculaObserve(t, "pending-while-isolated", lead)
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgCheckQuorum})
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgCheckQuorum})
	if lead.state != StateFollower {
		t.Fatalf("node 1 state = %v, want follower after quorum loss", lead.state)
	}
	speculaObserve(t, "after-stepdown", lead)

	nt.recover()
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgHup})
	if lead.state != StateLeader {
		t.Fatalf("node 1 state = %v, want leader again", lead.state)
	}
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	speculaObserve(t, "after-reelected-read", lead)
	_ = newReady(lead, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}
