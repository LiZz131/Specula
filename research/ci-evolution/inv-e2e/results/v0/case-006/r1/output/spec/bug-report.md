# Bug Report — etcd Raft V1 (updated source `update` c780d355)

## Summary

- Scenarios tested: 6 (V0 Scenarios 1–5 regression + update Scenario 6
  a–d)
- Model-checking bugs found: 1 (MC-1, update-attributed: the update removed
  the exact-old mask)
- Configs run: `MC.cfg`, `Update_full.cfg`, `Update_full_nk.cfg`,
  `Update_focused.cfg`, `Update_focused_nk.cfg`, `Update_open.cfg`,
  `Update_open_nk.cfg`, `Update_discharge.cfg`, `MC_hunt_s6_stale_ack.cfg`,
  `MC_hunt_s6_linearizable.cfg`, `MC_hunt_s6_linearizable_guided_noview.cfg`
  (+ simulation), inherited `MC_hunt_s1..s5`, `MC_complete_core.cfg`,
  reachability canaries `Reach_s1..s5`, `Reach_s6_*`. Outcomes:
  `spec/output/campaign-summary.md`.

## Bug 1: Reused ReadIndex context is released by an acknowledgement that predates it (stale linearizable read)

- **ID**: MC-1
- **Scenario**: 6b (delayed acknowledgement across context reuse), with 6a
- **Severity**: Medium (linearizability violation of ReadIndex; requires a
  caller to reuse a RequestCtx after its previous ReadState was produced, a
  delayed heartbeat response, and — for the stale value — a newer leader
  committing during a partition)
- **Invariant violated**: `UpdReadAckAfterEnqueue` (mechanism) and
  `UpdReadIndexLinearizable` (consumer-visible consequence)
- **Configs / counterexamples**:
  - consequence: `MC_hunt_s6_linearizable_guided_v2.cfg` — 37 states,
    `output/hunt-s6-linearizable-guided-v2.log`, `.cex.json`,
    `.cex-summary.txt` (`UpdReadIndexLinearizable`; found by TLC BFS under a
    search-only state constraint that adds no behavior, see `Update.tla`
    `S6GuideConstraintV2`)
  - mechanism: `MC_hunt_s6_stale_ack.cfg` — 21 states,
    `output/hunt-s6-stale-ack.log`, `.cex.json`, `.cex-summary.txt`
    (`UpdReadAckAfterEnqueue`)
  - mechanism on complete MCNext: `Update_full.cfg` — 22 states,
    `output/update-full.*` (variant where the stale response comes from the
    follower that also released the first read); `Update_focused.cfg` —
    `output/update-focused.*`
  - none of these counterexamples contains a Crash step, so they are
    unaffected by the later `Crash` repair.
- **Source**: model checking; real-implementation witnesses below.

### Trace Summary (`MC_hunt_s6_stale_ack`, 21 states)

1. States 2–13: s1 campaigns (term 1), s2/s3 vote, s1 becomes leader, its
   no-op is persisted, replicated to s3 and committed (commit 1).
2. State 14: `ClientReadIndex(s1, ctx1)` — first request for `ctx1` accepted
   (incarnation 1, index 1), heartbeats with `ctx1` to s2 and s3.
3. States 15–17: s2 answers; its response gives quorum → `advance` releases
   `ctx1`; **updated delete removes the `ctx1` pending entry**
   (`read_only.go:100-105`).
4. State 19: s3 processes the first-round heartbeat and generates its
   response (acknowledging leadership at that time) — the response stays in
   flight.
5. State 20: a second request with the same context `ctx1` is accepted
   (incarnation 2). The exact-old code would have ignored it (stale entry).
6. State 21: s3's response from state 19 is delivered; `recvAck` matches by
   context only (`read_only.go:64-73`), counts it, reaches quorum and
   releases the second request. Its only acknowledgement besides the leader
   was generated **before** the request was accepted:
   `freshAcks = {s1}` < Quorum.

### Consumer-visible consequence (stale read)

The same mechanism, combined with a partition in which a newer leader
commits, yields a read index below an index that was committed before the
read was accepted (`UpdReadIndexLinearizable`):

- **Real implementation trace, replayed by TLC**: `traces/stale_read_reuse.ndjson`
  (42 events from the instrumented updated code). `Trace_stale_read_reuse.cfg`
  consumes all events (conformance, TraceMatched);
  `Trace_stale_read_reuse_witness.cfg` reports `UpdReadIndexLinearizable`
  violated at the final event: s1 (stale leader of term 1) releases the reused
  `ctx1` read at index 2 after s2, leader of term 2, committed index 4.
  Logs: `output/trace-stale-read-reuse.log`,
  `output/trace-stale-read-reuse-witness.log`.
- **Code reachability test** (uninstrumented, both revisions):
  `harness/src/specula_s6_stale_read_test.go`; `spec/output/s6-stale-read-controls.log`:
  updated code FAILS (stale `ReadState{Index: 2}` after index 4 committed in
  term 2); baseline PASSES (the reused read is never answered).
- **Model counterexample** (`hunt-s6-linearizable-guided-v2`, 37 states):
  states 2–15 elect s1 (term 1) and commit its no-op; state 16 accepts the
  first `ctx1` read (index 1); state 17 s3 answers the read heartbeat (term-1
  response, delayed); state 18 s3 campaigns for term 2; states 21–22 s2's
  response releases the first read; states 25–35 s2 votes for s3, s3 becomes
  term-2 leader, replicates its no-op to s2 and commits index 2; state 36 the
  stale term-1 leader s1 accepts `ctx1` again (bound 2, index 1); state 37
  s3's term-1 response from state 17 is counted, the read is released at
  index 1 < 2 — `UpdReadIndexLinearizable` violated. The acknowledging node
  is the new leader itself, answering as a term-1 follower before it
  campaigned. `diag/PathCheck.tla` independently drives MCSpec along a
  38-step schedule of the same shape (diagnostic, `diag/pathcheck.log`).

### Root Cause

`readOnly` correlates a heartbeat response with a pending request only by the
caller context (`recvAck`, `read_only.go:64-73`; `advance`,
`read_only.go:78-109`). The update deletes released requests by their real
key (`read_only.go:103`), so the duplicate guard in `addRequest`
(`read_only.go:54-56`) no longer blocks a context that was used before. A
heartbeat response generated for the earlier use of that context — in flight
under message delay/reordering (rafttest/network.go:81-119) — is then counted
for the new request, and `stepLeader(MsgHeartbeatResp)` releases it with the
commit index captured at acceptance (`raft.go:915-932`). Nothing ties an
acknowledgement to the request instance or to a time after its acceptance,
which is what the ReadIndex confirmation round requires (leader authority
confirmed after the read arrives). In the exact-old code the never-deleted
entry made such reuse impossible (the second request was silently dropped —
itself a liveness/leak defect), which masked this path.

Premise/caller contract: `read_only.go:19-23` makes distinguishing returned
states by `RequestCtx` a caller duty, "eg. given a unique id". A caller that
reuses a context only after the previous ReadState was delivered can still
distinguish states (one outstanding request per context); the library gives
no warning, and the update's own test reuses literal contexts. With globally
unique contexts the path is unreachable.

### Affected Code

- `read_only.go:100-105` (`advance` deletes released keys — update)
- `read_only.go:52-58` (`addRequest` duplicate guard by context)
- `read_only.go:64-73` (`recvAck` matches by context only)
- `raft.go:824-853` (`stepLeader(MsgReadIndex)`: capture index, broadcast)
- `raft.go:903-932` (`stepLeader(MsgHeartbeatResp)`: count, advance, release)

### Recommendation

Bind acknowledgements to the request instance rather than to the caller
context, e.g. attach a leader-generated round identifier to the read
heartbeats and accept only responses carrying a round issued at or after the
pending request's acceptance; alternatively reject (or document as unsafe) a
RequestCtx reused while responses for its earlier use may be outstanding.

---

## Not Reproduced

Final artifacts (after the Crash repair); details in `output/campaign-summary.md`.

| Scenario | Config | States explored | Result |
|---|---|---|---|
| Standard reference invariants | `MC.cfg` | 16.9M distinct, depth 21 (30 min) | No violation; LIMITED_COVERAGE |
| Update properties except MC-1's, complete MCNext | `Update_full_nk.cfg` | 17.3M distinct, depth 22 (30 min) + simulation 84,587 traces (15 min) | No violation; LIMITED_COVERAGE |
| Concrete focused (Affected + Interaction) | `Update_focused_nk.cfg` | 5.7M distinct, depth 24 | No violation; LIMITED_COVERAGE |
| Open focused (with EnvUpdate) | `Update_open_nk.cfg` | 5.4M distinct, depth 15 | No violation; LIMITED_COVERAGE (provisional; weak EnvForward rely) |
| Discharge of EnvUpdate (CheckQuorum, ForwardReadIndex, LoseMessage) | `Update_discharge.cfg` | 3.1M distinct, depth 17; non-vacuity witness `Update_discharge_reach.cfg` depth 13 | No violation; LIMITED_COVERAGE |
| 1 Election | `MC_hunt_s1_election.cfg` | 16,456 distinct | Exhausted (counter-merged VIEW), no violation |
| 2 Replication | `MC_hunt_s2_replication.cfg` | 1.13M distinct, depth 17 | No violation; LIMITED_COVERAGE |
| 3 CheckQuorum | `MC_hunt_s3_quorum.cfg` | 4,912 distinct | Exhausted (counter-merged VIEW), no violation |
| 4 ReadIndex (V0 invariants) | `MC_hunt_s4_readindex.cfg` | 1.99M distinct, depth 19 + simulation | No violation; LIMITED_COVERAGE |
| 5 Forwarded ReadIndex | `MC_hunt_s5_forwarded_read.cfg` | 1.74M distinct, depth 23 + simulation | No violation; LIMITED_COVERAGE |
| Complete small core | `MC_complete_core.cfg` | 26,045 distinct, depth 23 | Exhausted (counter-merged VIEW), no violation |
| 6b unguided linearizability BFS | `MC_hunt_s6_linearizable.cfg` | 10.7M distinct, depth 28 | No violation within budget (target needs depth ~38); guided runs found MC-1 |

## Spec adjustments during this run

- Case A: `UpdReadAckFreshness` (r1, heartbeat-identity) revised to
  `UpdReadAckAfterEnqueue` (response generated after acceptance); r1 flagged a
  benign delayed-heartbeat interleaving. `spec/changelog.md`.
- Case B (V0 defect, not update-related): `Crash` now drops the crashing
  node's in-flight messages not yet justified by its durable state; it had
  produced a spurious `MCLeaderCompleteness` counterexample
  (`output/superseded-update-focused-nk-precrashfix.*`). No MC-1
  counterexample contains a Crash step.
- Search configuration: the inherited `VIEW MCView` omits fault counters and
  masked the 38-step S6b path in a bounded BFS; the guided S6b hunts run
  without the VIEW. No reference behavior or property was weakened.
