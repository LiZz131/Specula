# Bug Report — etcd Raft, `update` revision (incremental V1)

## Summary

- Update: `readOnly.advance` deletes released requests under their real key
  (`read_only.go:100-104`). Disposition MODEL_CHANGE_REQUIRED.
- Scenarios tested: 5 inherited (election, replication, quorum check, local
  ReadIndex, forwarded ReadIndex) + 6 update scenarios (US1-US6).
- Model-checking bugs found: **1** (MC-1), reproduced on the real update
  revision; absent on the baseline revision.
- Configs run: `MC.cfg` (standard, twice), `Update_full.cfg`,
  `Update_focused.cfg`, `Update_focused_reset.cfg`, `Update_open.cfg`,
  `Update_discharge.cfg` (+ negative control), `Update_hunt_us4_guided.cfg`,
  `Update_hunt_us4_focused.cfg`, `Update_hunt_us4_sim.cfg` (simulation),
  `MC_complete_core.cfg`, `MC_hunt_s1..s5`, `Reach_s1..s5`,
  `Update_reach_*` (4), `MC.cfg` simulation. Full inventory with coverage:
  `spec/output/mc/campaigns.md`.

## Bug 1: Reused ReadIndex context completed by a stale heartbeat acknowledgement yields a stale read index

- **Scenario**: US3 (mechanism) / US4 (consequence)
- **Severity**: Medium
- **Invariant violated**: `ReadIndexFreshness` (consequence);
  `ReadDeliveryJustifiedFresh` (mechanism)
- **Config**: `Update_hunt_us4_guided.cfg` (full `MCSpec`; the `US4Guide`
  CONSTRAINT only prunes the search); mechanism also in `Update_focused.cfg`
  and `Update_focused_reset.cfg` (`FocusedSpec` ⊆ `MCNext`: same MC wrappers and
  constraint, fewer disjuncts)
- **Counterexample**: 37 states, `spec/output/mc/hunt_us4_guided.log`
  (`.cex.json`, step summary `.cex.txt`); 22 states `update_focused.log`;
  21 states `update_focused_reset.log`. Final-artifact reruns:
  `final_hunt_us4_guided.log`, `final_update_focused.log`,
  `final_update_focused_reset.log` (regenerated on the final model: 37, 22, 21
  states); unguided simulation variant `sim_update_full.log` (44 states).

### Trace Summary (`hunt_us4_guided`)

1-14. s1 is elected leader of term 1 (Ready persistence before every send) and
commits its no-op at index 1 (s2's append response).
15. Client ReadIndex(ctx1) at s1: pending ctx1, index 1, request-time commit
watermark 1; heartbeats with Context ctx1 to s2 and s3.
16. s3 processes the heartbeat in term 1 and sends `MsgHeartbeatResp(ctx1, term 1)`
— this message is delayed.
17. s3 times out and campaigns for term 2.
20-21. s2 acknowledges; s1 reaches quorum and releases ctx1 (ReadState index 1);
**the update deletes ctx1 from pendingReadIndex**.
23-34. s2 votes for s3; s3 becomes leader of term 2, replicates its no-op to s2
and commits index 2 (term 2).
35. A client issues ReadIndex(ctx1) to s1 again; s1 is still leader of term 1
(no term-2 message reached it). Because ctx1 is no longer pending, `addRequest`
accepts it: index 1, request-time watermark 2.
36. s3's delayed term-1 acknowledgement from step 16 arrives; `recvAck` counts it
for the new request (2 >= quorum) and `advance` releases it.
37. Ready publishes ReadState{Index: 1, ctx1}, although index 2 was committed
before the request was issued (`ReadIndexFreshness`: index 1 < floor 2). The
acknowledgement set {s1, s3} contains no peer that acknowledged after the
request was accepted (`fresh` = {s1}).

The `update_focused_reset` variant needs no long delay: the periodic `MsgBeat`
heartbeat carries the last pending context (raft.go:457-464), so a second ack
for ctx1 arrives after the first release and completes the re-enqueued request.

Unguided simulation of the complete `MCNext` with crash/loss/quorum-check faults
(`sim_update_full.log`, 44 states) found a third variant: two *different*
followers (s1, s2) forward ReadIndex with the same context to leader s3; s1's
request is released by s2's ack, s1 then answers that heartbeat round, and that
ack — produced before s2's request was accepted — releases s2's forwarded
request (`ReadDeliveryJustifiedFresh`: acks {s1,s3}, fresh {s3}).

### Root Cause

- `read_only.go:100-104` (changed): released requests are deleted, so
  `read_only.go:52-58` (`addRequest`) admits the same caller context again in
  the same leader term.
- `read_only.go:64-73` (`recvAck`) and `raft.go:915-924` identify the request an
  acknowledgement belongs to **only** by `m.Context`; the ack carries the
  unchanged leader term and nothing that distinguishes request instances or
  heartbeat rounds. An ack produced before the new request was accepted is
  therefore counted for it.
- ReadIndex is safe only if a quorum confirms leadership *after* the request was
  accepted (README.md:27-29; node.go:154-157). An ack sent before the follower
  voted for a newer leader no longer confirms that.
- Baseline contrast: the old delete key `string(req.Context)` is empty for every
  MsgReadIndex (node.go:502-504, rawnode.go:262-264, raft.go:1068-1074), so the
  released entry stayed pending and the reused context was ignored (no stale
  read, but the second request was never answered and the map leaked).

### Affected Code

- `read_only.go:100-104`: release now deletes the request (enables re-admission).
- `read_only.go:52-58`: `addRequest` admits a released context again.
- `read_only.go:64-73`: `recvAck` matches acks to requests by context only.
- `raft.go:915-932`: `stepLeader` `MsgHeartbeatResp` quorum/advance/release.
- `raft.go:457-464`, `raft.go:824-838`: heartbeats carry the caller context.

### Reproduction

`harness/repro/specula_repro_readindex_test.go`, run by `harness/repro.sh` on
pristine exports (test file only), 3 runs each: update revision FAIL ("second
request for ctx "ctx" got read index 1, but index 3 was committed (by the
term-2 leader) before the request was issued"); baseline revision PASS (the
reused request is not served). Details: `spec/confirmation-MC-1.md`. Fresh
instrumented traces `traces/read_reuse.ndjson` and `traces/stale_read.ndjson`
replay in the model and violate the same properties
(`spec/evidence/Eval_*.log`).

### Recommendation

Make an acknowledgement count only for requests accepted before the heartbeat
it answers, e.g. send a leader-generated per-request/per-round identity as the
heartbeat context, or keep a released context unusable for the rest of the term
while still freeing its memory, or document and enforce caller context
uniqueness as a hard precondition of `ReadIndex`.

---

## Not Reproduced

Every run with mode, budget, states, and depth: `spec/output/mc/campaigns.md`.

| Scenario | Config | States explored | Result |
|---|---|---|---|
| Standard full model | `MC.cfg` (final) | 22,496,273 gen / 4,291,336 distinct, depth 31, 0 queued | No violation, EXHAUSTED |
| Complete small core | `MC_complete_core.cfg` | 109,936 / 26,255, depth 23 | No violation, EXHAUSTED |
| S1 election | `MC_hunt_s1_election.cfg` | 71,848 / 18,550, depth 18 | No violation, EXHAUSTED |
| S3 quorum | `MC_hunt_s3_quorum.cfg` | 25,861 / 4,912, depth 20 | No violation, EXHAUSTED |
| S2 replication | `MC_hunt_s2_replication.cfg` + simulation | 4,524,454 distinct, depth 19; 34,668 sim traces | No violation, LIMITED_COVERAGE |
| S4 local ReadIndex | `MC_hunt_s4_readindex.cfg` + simulation | 4,620,656 distinct, depth 20; 170,070 sim traces | No violation, LIMITED_COVERAGE |
| S5 forwarded ReadIndex | `MC_hunt_s5_forwarded_read.cfg` + simulation | 3,094,870 distinct, depth 24; 30,096 sim traces | No violation, LIMITED_COVERAGE |
| Update properties, full model | `Update_full.cfg` (final) | 15,646,198 distinct, depth 21 | No violation within budget (US3 found by its simulation follow-up), LIMITED_COVERAGE |
| Open focused (EnvUpdate) | `Update_open.cfg` (final) | 3,193,264 distinct, depth 18 | No violation, LIMITED_COVERAGE |
| Discharge | `Update_discharge.cfg` (final) | 1,492,681 distinct, depth 14 | `DischargeContext` holds within budget, LIMITED_COVERAGE; negative control refuted |
| US4 unguided | `Update_hunt_us4_focused.cfg` BFS + simulation, `Update_hunt_us4_sim.cfg` simulation | 10,377,769 distinct, depth 26; 30,756 + 263,174 sim traces | Not reached unguided within budget (found by the guided hunt) |
| Standard simulation | `MC.cfg` simulation | 246,708 traces | No violation, LIMITED_COVERAGE |

## Spec adjustments during model checking

- Case B (V1 draft ghost): `HandleReadIndexResponse` intersected acks across two
  matching release records when two justified releases of the same forwarded
  context produced identical responses (`superseded/sim_us4_full.pre-ghost-fix.*`,
  `superseded/hunt_us4_focused.pre-ghost-fix.*`). Fixed to an existential choice
  of one matching release; ghost-only. Affected campaigns rerun on the final
  artifacts. No property was weakened.
