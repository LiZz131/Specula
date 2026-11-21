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
// V1 update-focused scenarios (read_only.go:100-105 delete key). All three
// drive the real raft state machines; the in-tree network or explicit Step
// calls only route messages.

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

// TestSpeculaTraceReadReuse: old producer (heartbeat acks) -> affected
// advance/delete -> old consumer (addRequest duplicate guard) on reuse of a
// released context, then Ready publication of both reads.
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
	lead := speculaElectAndCommit(t, nt)
	for k := 0; k < 2; k++ {
		nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
			Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	}
	t.Logf("readStates=%d pending=%d queue=%d", len(lead.readStates),
		len(lead.readOnly.pendingReadIndex), len(lead.readOnly.readIndexQueue))
	_ = newReady(lead, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}

// TestSpeculaTraceForwardedRead: follower-originated request (forwarding
// path) through the affected leader release, the remote MsgReadIndexResp
// consumer, then reuse of the same context by the same follower.
func TestSpeculaTraceForwardedRead(t *testing.T) {
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
	lead := speculaElectAndCommit(t, nt)
	f := nt.peers[2].(*raft)
	for k := 0; k < 2; k++ {
		nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgReadIndex,
			Entries: []pb.Entry{{Data: []byte("ctx2")}}})
	}
	t.Logf("follower readStates=%d leader pending=%d queue=%d", len(f.readStates),
		len(lead.readOnly.pendingReadIndex), len(lead.readOnly.readIndexQueue))
	_ = newReady(f, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}

// TestSpeculaTraceDelayedAck: a follower's response to the first request's
// heartbeat is delivered only after the same context has been enqueued again;
// the second request's heartbeats are never delivered.
func TestSpeculaTraceDelayedAck(t *testing.T) {
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
	lead := speculaElectAndCommit(t, nt)
	f2 := nt.peers[2].(*raft)
	f3 := nt.peers[3].(*raft)
	read := pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}}

	lead.Step(read)
	var resp2, resp3 []pb.Message
	for _, hb := range lead.readMessages() {
		switch hb.To {
		case 2:
			f2.Step(hb)
			resp2 = f2.readMessages()
		case 3:
			f3.Step(hb)
			resp3 = f3.readMessages()
		}
	}
	if len(resp2) != 1 || len(resp3) != 1 {
		t.Fatalf("heartbeat responses = %d/%d, want 1/1", len(resp2), len(resp3))
	}
	lead.Step(resp2[0])
	if len(lead.readStates) != 1 {
		t.Fatalf("first read states = %d, want 1", len(lead.readStates))
	}
	lead.Step(read)
	withheld := lead.readMessages()
	lead.Step(resp3[0])
	t.Logf("withheld second-round heartbeats=%d readStates=%d", len(withheld), len(lead.readStates))
	_ = newReady(lead, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
}

// TestSpeculaTraceStepDownClearsReads: repair boundary for raft.reset
// (raft.go:489-511). A pending safe read exists when the leader broadcasts a
// MsgBeat heartbeat (lastPendingRequestCtx, raft.go:457-464) and then steps
// down on CheckQuorum (raft.go:791-796); becomeFollower installs a new
// readOnly.
func TestSpeculaTraceStepDownClearsReads(t *testing.T) {
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
	lead := speculaElectAndCommit(t, nt)
	f2 := nt.peers[2].(*raft)
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	_ = lead.readMessages() // read heartbeats withheld
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgBeat})
	for _, hb := range lead.readMessages() {
		if hb.To == 2 {
			f2.Step(hb)
			_ = f2.readMessages() // response withheld
		}
	}
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgCheckQuorum})
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgCheckQuorum})
	if lead.state != StateFollower {
		t.Fatalf("state = %v, want follower", lead.state)
	}
	t.Logf("after step-down pending=%d queue=%d", len(lead.readOnly.pendingReadIndex), len(lead.readOnly.readIndexQueue))
}

// TestSpeculaTraceHigherTermClearsReads: repair boundary for a higher-term
// MsgVote (raft.go:684-710 -> becomeFollower -> reset) received by a leader
// with a pending read, followed by the new leader's election.
func TestSpeculaTraceHigherTermClearsReads(t *testing.T) {
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
	lead := speculaElectAndCommit(t, nt)
	f2 := nt.peers[2].(*raft)
	f3 := nt.peers[3].(*raft)
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex,
		Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	_ = lead.readMessages() // read heartbeats withheld
	f2.Step(pb.Message{From: 2, To: 2, Type: pb.MsgHup})
	var resps []pb.Message
	for _, v := range f2.readMessages() {
		switch v.To {
		case 1:
			lead.Step(v)
			resps = append(resps, lead.readMessages()...)
		case 3:
			f3.Step(v)
			resps = append(resps, f3.readMessages()...)
		}
	}
	for _, r := range resps {
		f2.Step(r)
	}
	if f2.state != StateLeader || lead.state != StateFollower {
		t.Fatalf("states = %v/%v, want leader/follower", f2.state, lead.state)
	}
	t.Logf("old leader pending=%d queue=%d", len(lead.readOnly.pendingReadIndex), len(lead.readOnly.readIndexQueue))
}

// TestSpeculaTraceStaleReadReuse: S6b interaction on the real state machines
// (same schedule as harness/src/specula_s6_stale_read_test.go). s2's response
// to the first read's heartbeat is delayed; s2 then wins term 2 with s3 and
// commits "w"; s1, still leader of term 1, accepts a reused context and the
// delayed term-1 response releases it. Messages addressed to s1 after the
// first read are never delivered (partition), except the delayed response.
func TestSpeculaTraceStaleReadReuse(t *testing.T) {
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
	s1 := speculaElectAndCommit(t, nt)
	s2 := nt.peers[2].(*raft)
	s3 := nt.peers[3].(*raft)
	ctx := []byte("ctx1")
	read := pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}}

	s1.Step(read)
	var delayed []pb.Message
	for _, hb := range s1.readMessages() {
		switch hb.To {
		case 2:
			s2.Step(hb)
			delayed = append(delayed, s2.readMessages()...)
		case 3:
			s3.Step(hb)
			for _, resp := range s3.readMessages() {
				s1.Step(resp)
			}
		}
	}
	_ = s1.readMessages()
	if len(s1.readStates) != 1 || len(delayed) != 1 {
		t.Fatalf("first read: readStates=%d delayed=%d", len(s1.readStates), len(delayed))
	}
	_ = newReady(s1, &SoftState{Lead: None, RaftState: StateFollower}, emptyState)
	s1.readStates = nil // delivered by node.run after Ready (node.go:355-373)

	deliver := func(msgs []pb.Message) []pb.Message {
		var out []pb.Message
		for _, m := range msgs {
			switch m.To {
			case 2:
				s2.Step(m)
				out = append(out, s2.readMessages()...)
			case 3:
				s3.Step(m)
				out = append(out, s3.readMessages()...)
			}
		}
		return out
	}
	s2.Step(pb.Message{From: 2, To: 2, Type: pb.MsgHup})
	for msgs := s2.readMessages(); len(msgs) > 0; {
		msgs = deliver(msgs)
		msgs = append(msgs, s2.readMessages()...)
	}
	s2.Step(pb.Message{From: 2, To: 2, Type: pb.MsgProp, Entries: []pb.Entry{{Data: []byte("v1")}}})
	for msgs := s2.readMessages(); len(msgs) > 0; {
		msgs = deliver(msgs)
		msgs = append(msgs, s2.readMessages()...)
	}
	s1.Step(read)
	_ = s1.readMessages()
	s1.Step(delayed[0])
	t.Logf("s2 term=%d committed=%d; s1 term=%d readStates=%v", s2.Term, s2.raftLog.committed, s1.Term, s1.readStates)
}
