package raft

import (
	"testing"

	pb "github.com/coreos/etcd/raft/raftpb"
)

// Source-derived update probes (read_only.go:advance delete key). They drive
// the real raft state machine directly through raft.Step with explicit,
// manually ordered message delivery; nothing is simulated. Results are logged
// so the same test can be run against the baseline and update revisions.

func speculaProbeLeader(t *testing.T) *raft {
	r := newTestRaft(1, []uint64{1, 2, 3}, 10, 1, NewMemoryStorage())
	r.becomeCandidate()
	r.becomeLeader()
	// Commit the leader's current-term no-op so safe reads are eligible.
	r.Step(pb.Message{From: 2, To: 1, Type: pb.MsgAppResp, Term: r.Term, Index: r.raftLog.lastIndex()})
	if r.raftLog.committed != r.raftLog.lastIndex() {
		t.Fatalf("committed = %d, want %d", r.raftLog.committed, r.raftLog.lastIndex())
	}
	r.readMessages()
	return r
}

// TestSpeculaProbeContextReuse: a caller reuses a RequestCtx only after the
// ReadState for its previous use was produced.
func TestSpeculaProbeContextReuse(t *testing.T) {
	r := speculaProbeLeader(t)
	ctx := []byte("ctx1")
	r.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	r.readMessages()
	r.Step(pb.Message{From: 2, To: 1, Type: pb.MsgHeartbeatResp, Term: r.Term, Context: ctx})
	first := len(r.readStates)
	r.readStates = nil
	t.Logf("first read: readStates=%d queue=%d pending=%d", first, len(r.readOnly.readIndexQueue), len(r.readOnly.pendingReadIndex))
	r.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	hb := r.readMessages()
	t.Logf("second read enqueue: heartbeats=%d queue=%d pending=%d", len(hb), len(r.readOnly.readIndexQueue), len(r.readOnly.pendingReadIndex))
	r.Step(pb.Message{From: 3, To: 1, Type: pb.MsgHeartbeatResp, Term: r.Term, Context: ctx})
	t.Logf("second read after fresh ack: readStates=%d queue=%d pending=%d", len(r.readStates), len(r.readOnly.readIndexQueue), len(r.readOnly.pendingReadIndex))
}

// TestSpeculaProbeDelayedAck: follower 3 answers the first read's heartbeat
// but its response is delivered only after the same context was enqueued
// again. No heartbeat for the second request reaches any follower.
func TestSpeculaProbeDelayedAck(t *testing.T) {
	r := speculaProbeLeader(t)
	ctx := []byte("ctx1")
	r.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	r.readMessages()
	delayed := pb.Message{From: 3, To: 1, Type: pb.MsgHeartbeatResp, Term: r.Term, Context: ctx}
	r.Step(pb.Message{From: 2, To: 1, Type: pb.MsgHeartbeatResp, Term: r.Term, Context: ctx})
	t.Logf("first read: readStates=%d", len(r.readStates))
	r.readStates = nil
	r.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: ctx}}})
	r.readMessages() // second-round heartbeats are never delivered
	r.Step(delayed)
	t.Logf("second read after delayed first-round ack only: readStates=%d queue=%d pending=%d", len(r.readStates), len(r.readOnly.readIndexQueue), len(r.readOnly.pendingReadIndex))
}

// TestSpeculaProbeEmptyContext: a released non-empty request is deleted by
// string(req.Context) in the exact-old advance. Requests carry no Context, so
// the old code deletes key "" -- the key of a still-queued empty-context
// request -- and a later advance walks the queue into a missing map entry.
func TestSpeculaProbeEmptyContext(t *testing.T) {
	r := speculaProbeLeader(t)
	defer func() {
		if p := recover(); p != nil {
			t.Logf("PANIC: %v", p)
		}
	}()
	for _, c := range []string{"a", "", "b"} {
		r.Step(pb.Message{From: 1, To: 1, Type: pb.MsgReadIndex, Entries: []pb.Entry{{Data: []byte(c)}}})
	}
	r.readMessages()
	r.Step(pb.Message{From: 2, To: 1, Type: pb.MsgHeartbeatResp, Term: r.Term, Context: []byte("a")})
	t.Logf("after ack a: readStates=%d queue=%q pending=%d", len(r.readStates), r.readOnly.readIndexQueue, len(r.readOnly.pendingReadIndex))
	r.Step(pb.Message{From: 2, To: 1, Type: pb.MsgHeartbeatResp, Term: r.Term, Context: []byte("b")})
	t.Logf("after ack b: readStates=%d queue=%q pending=%d", len(r.readStates), r.readOnly.readIndexQueue, len(r.readOnly.pendingReadIndex))
}
