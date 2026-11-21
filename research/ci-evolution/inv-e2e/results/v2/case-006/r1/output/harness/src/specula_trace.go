package raft

import (
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"strings"
	"sync"
	"time"

	pb "github.com/coreos/etcd/raft/raftpb"
)

// This file is test-only instrumentation for the Specula V0 harness. Calls are
// no-ops unless speculaTraceStart has enabled a writer.
var speculaTrace struct {
	sync.Mutex
	f *os.File
}

type speculaTraceState struct {
	Term           uint64   `json:"term"`
	Vote           string   `json:"vote"`
	Role           string   `json:"role"`
	Leader         string   `json:"leader"`
	Commit         uint64   `json:"commit"`
	Applied        uint64   `json:"applied"`
	LogTerms       []uint64 `json:"logTerms"`
	ReadQueue      []string `json:"readQueue"`
	PendingCount   int      `json:"pendingCount"`
	ReadCount      int      `json:"readCount"`
	ReadyReadCount int      `json:"readyReadCount"`
	// Update-mandatory fields (incremental revision c780d355): the exact
	// pendingReadIndex contents and the produced readStates.
	Pending    []speculaPending   `json:"pending"`
	ReadStates []speculaReadState `json:"readStates"`
}

type speculaPending struct {
	Ctx   string   `json:"ctx"`
	Index uint64   `json:"index"`
	From  string   `json:"from"`
	Acks  []string `json:"acks"`
}

type speculaReadState struct {
	Index uint64 `json:"index"`
	Ctx   string `json:"ctx"`
}

type speculaTraceMsg struct {
	Type      string `json:"type"`
	From      string `json:"from"`
	To        string `json:"to"`
	Term      uint64 `json:"term"`
	Index     uint64 `json:"index"`
	LogTerm   uint64 `json:"logTerm"`
	Commit    uint64 `json:"commit"`
	EntryTerm uint64 `json:"entryTerm"`
	Value     string `json:"value"`
	Ctx       string `json:"ctx"`
	Reject    bool   `json:"reject"`
}

func speculaNodeID(id uint64) string {
	if id == None {
		return "Nil"
	}
	return fmt.Sprintf("s%d", id)
}

func speculaTraceStart(path string) error {
	speculaTrace.Lock()
	defer speculaTrace.Unlock()
	f, err := os.Create(path)
	if err != nil {
		return err
	}
	speculaTrace.f = f
	return nil
}

func speculaTraceStop() error {
	speculaTrace.Lock()
	defer speculaTrace.Unlock()
	if speculaTrace.f == nil {
		return nil
	}
	err := speculaTrace.f.Close()
	speculaTrace.f = nil
	return err
}

func speculaCaptureState(r *raft, readyReads int) speculaTraceState {
	terms := make([]uint64, 0, r.raftLog.lastIndex())
	for _, e := range r.raftLog.allEntries() {
		terms = append(terms, e.Term)
	}
	queue := make([]string, len(r.readOnly.readIndexQueue))
	copy(queue, r.readOnly.readIndexQueue)
	role := strings.TrimPrefix(r.state.String(), "State")
	pending := make([]speculaPending, 0, len(r.readOnly.pendingReadIndex))
	for key, rs := range r.readOnly.pendingReadIndex {
		from := rs.req.From
		if from == None {
			// raft.go:927 treats a request without From as local.
			from = r.id
		}
		acks := make([]string, 0, len(rs.acks))
		for id := range rs.acks {
			acks = append(acks, speculaNodeID(id))
		}
		sort.Strings(acks)
		pending = append(pending, speculaPending{Ctx: key, Index: rs.index,
			From: speculaNodeID(from), Acks: acks})
	}
	sort.Slice(pending, func(a, b int) bool { return pending[a].Ctx < pending[b].Ctx })
	readStates := make([]speculaReadState, 0, len(r.readStates))
	for _, rs := range r.readStates {
		readStates = append(readStates, speculaReadState{Index: rs.Index, Ctx: string(rs.RequestCtx)})
	}
	return speculaTraceState{
		Term: r.Term, Vote: speculaNodeID(r.Vote), Role: role,
		Leader: speculaNodeID(r.lead), Commit: r.raftLog.committed,
		Applied: r.raftLog.applied, LogTerms: terms, ReadQueue: queue,
		PendingCount: len(r.readOnly.pendingReadIndex),
		ReadCount:    len(r.readStates), ReadyReadCount: readyReads,
		Pending:      pending, ReadStates: readStates,
	}
}

func speculaCaptureMsg(m *pb.Message) *speculaTraceMsg {
	if m == nil {
		return nil
	}
	tm, value := uint64(0), "Nil"
	if len(m.Entries) != 0 {
		e := m.Entries[len(m.Entries)-1]
		tm = e.Term
		if len(e.Data) != 0 {
			value = string(e.Data)
		}
	}
	ctx := "Nil"
	if len(m.Context) != 0 {
		ctx = string(m.Context)
	} else if m.Type == pb.MsgReadIndex && len(m.Entries) != 0 {
		ctx = string(m.Entries[0].Data)
	}
	if m.Type == pb.MsgReadIndex || m.Type == pb.MsgReadIndexResp {
		// Read requests/responses carry the caller context in Entries[0].Data
		// (node.go:502-504, raft.go:930); the model's message has no entry.
		tm, value = 0, "Nil"
		if len(m.Entries) != 0 && len(m.Entries[0].Data) != 0 {
			ctx = string(m.Entries[0].Data)
		}
	}
	return &speculaTraceMsg{
		Type: m.Type.String(), From: speculaNodeID(m.From),
		To: speculaNodeID(m.To), Term: m.Term, Index: m.Index,
		LogTerm: m.LogTerm, Commit: m.Commit, EntryTerm: tm,
		Value: value, Ctx: ctx, Reject: m.Reject,
	}
}

func speculaTraceEmit(r *raft, name string, m *pb.Message, readyReads int) {
	speculaTrace.Lock()
	defer speculaTrace.Unlock()
	if speculaTrace.f == nil {
		return
	}
	event := map[string]interface{}{
		"name":  name,
		"nid":   speculaNodeID(r.id),
		"state": speculaCaptureState(r, readyReads),
	}
	if msg := speculaCaptureMsg(m); msg != nil {
		event["msg"] = msg
	}
	record := map[string]interface{}{
		"tag": "trace", "ts": time.Now().UnixNano(), "event": event,
	}
	b, err := json.Marshal(record)
	if err != nil {
		panic(err)
	}
	if _, err = speculaTrace.f.Write(append(b, '\n')); err != nil {
		panic(err)
	}
	if err = speculaTrace.f.Sync(); err != nil {
		panic(err)
	}
}
