# MC-1 — reproduction and confirmation evidence

**Finding**: a released ReadIndex context can be enqueued again in the same term
and completed by an acknowledgement produced before that request existed,
yielding a stale (non-linearizable) read index.

- **Source**: model checking (actual counterexamples) — `ReadDeliveryJustifiedFresh`
  (`spec/output/mc/update_focused.log`, `update_focused_reset.log`) and
  `ReadIndexFreshness` (`spec/output/mc/hunt_us4_guided.log`).
- **Novelty**: no prior Specula finding (prior `findings.json` empty); the
  `specula findings` registry CLI is not installed in this environment, so no
  registry lookup could be run. No external sources were consulted (blind run).
- **Status (this run)**: REPRODUCED on the `update` revision; not present on the
  `baseline` revision. The controller-side confirmation workflow
  (`request_bug_confirmation`) is not available here; this file records the
  reproduction performed within Validation/Model Checking following the
  bug-confirmation method.
- **Severity**: Medium (linearizability violation; requires the caller to reuse a
  ReadIndex context after its earlier request completed, a delayed or
  duplicated heartbeat acknowledgement, and a leadership change).

## Code path (update revision)

1. `stepLeader` `MsgReadIndex` (raft.go:824-838): `addRequest(committed, m)`,
   `bcastHeartbeatWithCtx(ctx)`. The periodic `bcastHeartbeat`
   (raft.go:457-464) also carries the last pending context.
2. Follower `handleHeartbeat` echoes `Context` in `MsgHeartbeatResp`
   (raft.go:1099-1102) at its current term.
3. Leader `MsgHeartbeatResp` (raft.go:915-932): `recvAck` (read_only.go:64-73)
   counts `m.From` for whatever request is pending under `m.Context`; at quorum,
   `advance` releases the queue prefix and — **changed line** read_only.go:103 —
   deletes each released entry under `string(rs.req.Entries[0].Data)`.
4. Because the entry is gone, `addRequest` (read_only.go:52-58) accepts the same
   context again in the same term with a new captured index.
5. Any acknowledgement still in flight from step 2 matches the new entry by
   context alone; nothing ties an ack to the request instance (no term/round/
   index in the ack; ack term equals the unchanged leader term). It can supply
   the quorum for the new request although the acking follower answered before
   the new request was accepted — possibly before it voted for a newer leader.

On the `baseline` revision step 3 deleted key `string(req.Context)` (empty for
every MsgReadIndex built by node.go:502-504 / rawnode.go:262-264), so step 4
ignored the reused context forever (the second request is never served) and
step 5 could not attribute an old ack to a new request.

Requirement: node.go:154-157 and rawnode.go:258-261 ("Once the application
advances further than the read index, any linearizable read requests issued
before the read request can be processed safely"); node.go:63-66; README.md:27-29
("leader checks with quorum ... before processing read-only queries"). No API
text makes context uniqueness a safety precondition: read_only.go:19-23 asks the
caller to *differentiate* returned states (e.g. by a unique id), and
`TestReadOnlyForNewLeader` (raft_test.go:1949-1970) issues the same context twice.

## Reproduction (escalation level 0: real raft state machines, in-tree test
## network, only legitimate messages; the only adversary is message delay)

Test: `harness/repro/specula_repro_readindex_test.go`
(`TestSpeculaReproStaleReadAfterContextReuse`), run on a pristine export of each
revision with only this test file added:

```
TARGET_REV=c780d355cfeae6ee6be52c50c1f0bd7d30c6657a harness/repro.sh spec/output/repro/repro-new-update.log
TARGET_REV=7289d1c5e049933b90a9692bbf508714bee02fce harness/repro.sh spec/output/repro/repro-old-baseline.log
# inside: go test -vet=off github.com/coreos/etcd/raft -count=3 -v \
#   -run '^(TestSpeculaReproStaleReadAfterContextReuse|TestRaftFreesReadOnlyMem)$'
```

Sequence: node 1 leads term 1 and commits; ReadIndex("ctx") is released by node
2's ack while node 3's ack for the same heartbeat round is delayed; node 1 is
partitioned; nodes 2/3 elect node 2 (term 2), which commits a write (index 3);
the client issues a new ReadIndex("ctx") to node 1 (still leader of term 1,
commit 1); node 3's delayed term-1 ack is delivered.

Update revision output (3/3 runs, `spec/output/repro/repro-new-update.log`):

```
specula_repro_readindex_test.go:92: stale ReadIndex: second request for ctx "ctx" got read index 1, but index 3 was committed (by the term-2 leader) before the request was issued
--- FAIL: TestSpeculaReproStaleReadAfterContextReuse (0.00s)
--- PASS: TestRaftFreesReadOnlyMem (0.00s)
exit=1
```

Baseline control (3/3 runs, `spec/output/repro/repro-old-baseline.log`):
`readStates=[]` after the second request (it is silently ignored — the old
liveness defect), `--- PASS`, `exit=0`.

Expected correct behaviour: either no ReadState for the second request until a
quorum acknowledges node 1 *after* that request was accepted (impossible here,
since nodes 2/3 are in term 2), or a ReadState whose index covers index 3.

## Match with the counterexamples

- `hunt_us4_guided` (37 states): identical shape — ack produced in term 1,
  acker then participates in a term-2 election and commit, the old leader
  re-accepts the context with floor 2 / index 1, the old ack releases it, Ready
  publishes it (`ReadIndexFreshness`).
- `update_focused` / `update_focused_reset`: the mechanism without a newer
  leader (`ReadDeliveryJustifiedFresh`); the latter shows that the periodic
  `MsgBeat` heartbeat carrying the pending context produces the duplicate ack
  without any long message delay.
- Fresh implementation traces `traces/read_reuse.ndjson` and
  `traces/stale_read.ndjson` replay in the model and violate the same two
  properties (`spec/evidence/Eval_*.log`).

## Recommendation

Do not let an acknowledgement produced before a request was accepted count for
it, e.g. attach a leader-generated per-request (or per-heartbeat-round) identity
to the heartbeat context instead of the raw caller context, or keep released
contexts unavailable for re-use within the term while still freeing memory
(e.g. record the release index/term); alternatively document and enforce caller
context uniqueness as a hard precondition.
