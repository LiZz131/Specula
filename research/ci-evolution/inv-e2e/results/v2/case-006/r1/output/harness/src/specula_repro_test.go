package raft

import (
	"testing"

	pb "github.com/coreos/etcd/raft/raftpb"
)

// Specula reproduction for MC-U1/MC-U2 (incremental update c780d355).
// Oracle: node.go:155-157 — "Once the application advances further than the
// read index, any linearizable read requests issued before the read request
// can be processed safely." A ReadState returned for a request issued after
// an entry was committed must therefore have Index >= that entry's index.
// Uses only APIs present in both the baseline and the update revision.

func speculaReproSetup(t *testing.T) (*network, *raft, *raft, *raft) {
	nt := newNetwork(nil, nil, nil)
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgHup})
	lead := nt.peers[1].(*raft)
	if lead.state != StateLeader {
		t.Fatalf("node 1 state = %v, want leader", lead.state)
	}
	nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgProp, Entries: []pb.Entry{{Data: []byte("v1")}}})
	return nt, lead, nt.peers[2].(*raft), nt.peers[3].(*raft)
}

// round1 registers ctx at the leader, delivers the heartbeat to node 3 and
// node 3's ack to the leader, and returns node 2's (delayed) response.
func speculaReproRound1(t *testing.T, lead, n2, n3 *raft, ctx []byte) pb.Message {
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	var delayed []pb.Message
	for _, hb := range lead.readMessages() {
		switch hb.To {
		case 2:
			n2.Step(hb)
			delayed = n2.readMessages()
		case 3:
			n3.Step(hb)
			for _, resp := range n3.readMessages() {
				lead.Step(resp)
			}
		}
	}
	lead.readMessages()
	if len(lead.readStates) != 1 || len(delayed) != 1 || delayed[0].Type != pb.MsgHeartbeatResp {
		t.Fatalf("round 1 setup: readStates=%d delayed=%v", len(lead.readStates), delayed)
	}
	return delayed[0]
}

func speculaReproNewerLeader(t *testing.T, nt *network, lead, n2 *raft) uint64 {
	nt.isolate(1)
	nt.send(pb.Message{From: 2, To: 2, Type: pb.MsgHup})
	if n2.state != StateLeader || n2.Term <= lead.Term || n2.raftLog.committed <= lead.raftLog.committed {
		t.Fatalf("setup: node 2 state=%v term=%d committed=%d", n2.state, n2.Term, n2.raftLog.committed)
	}
	return n2.raftLog.committed
}

// TestSpeculaReproStaleReadAfterContextReuse: the same caller context is used
// for a second read after the first completed; a delayed term-1 ack produced
// for the first request completes the second one.
func TestSpeculaReproStaleReadAfterContextReuse(t *testing.T) {
	nt, lead, n2, n3 := speculaReproSetup(t)
	ctx := []byte("ctx1")
	delayed := speculaReproRound1(t, lead, n2, n3, ctx)
	committedBefore := speculaReproNewerLeader(t, nt, lead, n2)

	lead.readStates = nil // the application consumed the first ReadState
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	lead.readMessages() // round-2 heartbeats never arrive
	lead.Step(delayed)
	t.Logf("old leader term=%d state=%v pending=%d readStates=%+v; newer leader term=%d committed=%d before the read",
		lead.Term, lead.state, len(lead.readOnly.pendingReadIndex), lead.readStates, n2.Term, committedBefore)
	for _, rs := range lead.readStates {
		if rs.Index < committedBefore {
			t.Errorf("STALE READ: ReadState{Index:%d, ctx:%q} returned for a request issued after index %d was committed in term %d",
				rs.Index, rs.RequestCtx, committedBefore, n2.Term)
		}
	}
}

// TestSpeculaReproUniqueContextControl: identical schedule, but the second
// request uses a fresh context. The delayed ack cannot complete it.
func TestSpeculaReproUniqueContextControl(t *testing.T) {
	nt, lead, n2, n3 := speculaReproSetup(t)
	delayed := speculaReproRound1(t, lead, n2, n3, []byte("ctx1"))
	committedBefore := speculaReproNewerLeader(t, nt, lead, n2)
	lead.readStates = nil
	lead.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: []byte("ctx2")}}})
	lead.readMessages()
	lead.Step(delayed)
	t.Logf("control: readStates=%+v pending=%d", lead.readStates, len(lead.readOnly.pendingReadIndex))
	for _, rs := range lead.readStates {
		if rs.Index < committedBefore {
			t.Errorf("STALE READ with unique context: %+v", rs)
		}
	}
}

// TestSpeculaReproContextReuseServed: a reused context is answered again
// under normal delivery (the liveness behavior the update restores).
func TestSpeculaReproContextReuseServed(t *testing.T) {
	nt, lead, _, _ := speculaReproSetup(t)
	for i := 0; i < 2; i++ {
		nt.send(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: []byte("ctx1")}}})
	}
	t.Logf("readStates=%+v pending=%d queue=%d", lead.readStates,
		len(lead.readOnly.pendingReadIndex), len(lead.readOnly.readIndexQueue))
	if len(lead.readStates) != 2 {
		t.Errorf("reused context answered %d times, want 2", len(lead.readStates))
	}
}
