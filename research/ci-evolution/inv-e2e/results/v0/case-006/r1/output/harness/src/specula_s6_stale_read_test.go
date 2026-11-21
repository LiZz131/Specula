package raft

import (
	"testing"

	pb "github.com/coreos/etcd/raft/raftpb"
)

// TestSpeculaS6StaleReadAfterContextReuse checks, on the real raft state
// machines, the S6b interaction found by the model:
//
//  1. s1 leads term 1 and serves a safe read for RequestCtx "ctx" with s3's
//     acknowledgement; s2's response to the same heartbeat is delayed.
//  2. s1 is cut off; s2 wins term 2 with s3's vote and commits a new entry
//     ("w") with s3 -- a write that completes before the next read starts.
//  3. A caller reuses "ctx" for a new read on s1 (its previous ReadState was
//     already produced); s1 still believes it leads term 1.
//  4. s2's delayed term-1 response is delivered to s1.
//
// Only message routing/delay is controlled by the test. The test FAILS when
// s1 produces a ReadState for the second read whose index is below the index
// of "w" (a stale linearizable read), and PASSES otherwise.
func TestSpeculaS6StaleReadAfterContextReuse(t *testing.T) {
	nt := newNetwork(nil, nil, nil)
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgHup})
	s1 := nt.peers[1].(*raft)
	s2 := nt.peers[2].(*raft)
	s3 := nt.peers[3].(*raft)
	if s1.state != StateLeader {
		t.Fatalf("s1 state = %v, want leader", s1.state)
	}
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgProp, Entries: []pb.Entry{{Data: []byte("v1")}}})
	ctx := []byte("ctx")

	// (1) first read; s2's acknowledgement is held back.
	s1.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
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
		t.Fatalf("first read: readStates=%d delayed=%d, want 1/1", len(s1.readStates), len(delayed))
	}
	first := s1.readStates[0]
	s1.readStates = nil // delivered to the application via Ready (node.go:355-373)

	// (2) s1 cut off; s2 elected in term 2 with s3 and commits "w" with s3.
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
	if s2.state != StateLeader || s2.Term != 2 {
		t.Fatalf("s2 state=%v term=%d, want leader term 2", s2.state, s2.Term)
	}
	s2.Step(pb.Message{From: 2, To: 2, Type: pb.MsgProp, Entries: []pb.Entry{{Data: []byte("w")}}})
	for msgs := s2.readMessages(); len(msgs) > 0; {
		msgs = deliver(msgs)
		msgs = append(msgs, s2.readMessages()...)
	}
	wIndex := s2.raftLog.lastIndex()
	if s2.raftLog.committed != wIndex {
		t.Fatalf("w not committed by s2: committed=%d last=%d", s2.raftLog.committed, wIndex)
	}

	// (3) context reused on the old leader; its heartbeats never arrive.
	if s1.state != StateLeader || s1.Term != 1 {
		t.Fatalf("s1 state=%v term=%d, want stale leader in term 1", s1.state, s1.Term)
	}
	s1.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	_ = s1.readMessages()

	// (4) delayed term-1 acknowledgement from s2 arrives.
	s1.Step(delayed[0])
	t.Logf("first ReadState index=%d; w committed by term-2 leader at index %d; second-read ReadStates=%v",
		first.Index, wIndex, s1.readStates)
	for _, rs := range s1.readStates {
		if rs.Index < wIndex {
			t.Fatalf("stale read: old leader (term %d) produced ReadState{Index: %d, Ctx: %q} for a read issued after index %d was committed in term %d",
				s1.Term, rs.Index, rs.RequestCtx, wIndex, s2.Term)
		}
	}
}
