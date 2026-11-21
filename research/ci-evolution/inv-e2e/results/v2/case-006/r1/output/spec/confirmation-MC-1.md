# Confirmation MC-1 — Reused ReadIndex context released by an acknowledgement produced for the earlier request

- **Status**: REPRODUCED
- **Source**: model-checking (actual TLC counterexamples from Init; see below)
- **Novelty**: NEW within this run. No persistent-findings store or `specula`
  CLI is available in this environment; the prior V0 suite has an empty
  findings list, so there was nothing to match. No external tracker was
  consulted (blind run).
- **Severity**: Medium (linearizability violation of the safe ReadIndex path;
  requires caller context reuse, a delayed heartbeat response and a newer-term
  commit before the old leader steps down)
- **Update attribution**: introduced by the update. The update removes the
  mask that blocked the trigger: exact-old never freed released requests, so a
  reused context was never registered again within a leader term.
- **Source revision**: artifact `c780d355cfeae6ee6be52c50c1f0bd7d30c6657a`
  (`update`); control `7289d1c5e049933b90a9692bbf508714bee02fce` (`baseline`).

## Mechanism

1. `addRequest` keys a safe read by the caller context
   (`read_only.go:52-59`) and ignores a context that is still pending.
2. `recvAck` matches a heartbeat response to a pending request only by
   `string(m.Context)` and the response's sender (`read_only.go:64-73`).
   Heartbeats and their responses carry only the term and the context
   (`raft.go:427-443`, `raft.go:1112-1115`); nothing binds a response to a
   particular registration.
3. The update makes `advance` delete every released request
   (`read_only.go:100-105`). After a context `c` is released, a new request
   with the same `c` is registered again in the same term.
4. A heartbeat response produced for the *earlier* registration of `c` and
   still in flight is then counted for the *new* registration
   (`raft.go:915-932`), so the new request is released without any
   acknowledgement generated after it was registered.
5. If, in between, the other servers elected a newer leader and committed an
   entry, the old leader (same term, not yet stepped down; `CheckQuorum` is
   optional and off by default, `raft.go:155-157`, `raft.go:542`) returns a
   ReadState whose index is lower than that committed entry.

Contract violated: `node.go:155-157` ("Once the application advances further
than the read index, any linearizable read requests issued before the read
request can be processed safely") and `raft.go:47-48` ("ReadOnlySafe
guarantees the linearizability of the read only request by communicating with
the quorum").

## Model-checking evidence

All counterexamples start from Init; every one replays step by step under the
complete `MCNext` (`spec/admit/admit-*-under-MCNext.log`, or was produced by
the complete `MCSpec` itself).

| Property | Config | States | Files |
|---|---|---|---|
| `UpdReadAckFresh` | `Update_hunt_stale_ack.cfg` (BFS-shortest) | 21 | `spec/output/mc-upd_hunt_stale_ack.log`, `spec/output/cex/upd_hunt_stale_ack.{json,tla,steps.md}` |
| `UpdReadAckFresh` | `Update_focused.cfg` | 19 | `spec/output/mc-upd_focused.log`, `spec/output/cex/upd_focused.*`; admission `spec/admit/admit-upd_focused-under-MCNext.log` |
| `UpdReadAckFresh` | `Update_full.cfg` simulation (complete `MCNext`, forwarded reads) | 47 | `spec/output/mc-upd_full_sim.log`, `spec/output/cex/upd_full_sim.*`; admission `spec/admit/admit-UpdFullSim-under-MCNext.log` |
| `UpdReadAckFresh` | `Update_hunt_forwarded.cfg`, `Update_open.cfg` | 21, 19 | `spec/output/mc-upd_hunt_forwarded.log`, `spec/output/mc-upd_open.log`, `spec/output/cex/` |
| `UpdReadIndexLinearizable` | `Update_hunt_linearizable_directed.cfg` (phase-guarded subset of `MCNext`) | 35 | `spec/output/mc-upd_hunt_linearizable_directed.log`, `spec/output/cex/upd_hunt_linearizable_directed.*`; admission `spec/admit/admit-UpdLinDirected-under-MCNext.log` |

Trace-grounded: the real implementation execution
`traces/stale_ack_reuse.ndjson` replays completely on the updated model
(`Trace_stale_ack.cfg`), and its final state violates both `UpdReadAckFresh`
and `UpdReadIndexLinearizable` while `ReadDeliveryJustified` holds
non-vacuously (`spec/output/trace-stale_ack_reuse-evidence-{fresh,lin}.log`).

## Reproduction (real interface: `raft.Step` + in-tree test network)

Test: `harness/src/specula_repro_test.go`, run by `harness/repro.sh`
(bounded `go test`, log `spec/output/repro.log`).

| Test | Update c780d355 | Baseline 7289d1c5 |
|---|---|---|
| `TestSpeculaReproStaleReadAfterContextReuse` | **FAIL**: `STALE READ: ReadState{Index:2, ctx:"ctx1"} returned for a request issued after index 3 was committed in term 2` | PASS: the second ctx1 request is never registered (stale entry), no ReadState |
| `TestSpeculaReproUniqueContextControl` (second request uses `ctx2`) | PASS (no ReadState from the delayed ack) | PASS |
| `TestSpeculaReproContextReuseServed` (normal delivery) | PASS (reused context answered twice) | FAIL (reused context answered once: exact-old leak/liveness defect fixed by the update) |

Escalation level: deterministic unit-level reproduction through the public
state-machine API (`Step`) with explicit message scheduling; no fault
injection beyond message delay and a network partition from the in-tree test
network.

## Premises

- The application reuses a ReadIndex request context after the earlier request
  with that context completed. The API documents the context as caller-chosen
  and only suggests a unique id for differentiating results
  (`read_only.go:19-23`); in-tree tests reuse a context across requests
  (`raft_test.go:1948-1970`, `node_test.go:206-230`).
- A heartbeat response for the earlier request is delayed until after the
  re-registration (message delay/reordering is in the fault model).
- For the stale-read consequence: a newer leader commits before the reused
  request is issued, while the old leader still considers itself leader in the
  old term.

## Recommendation

Bind acknowledgements to a registration rather than to the caller context —
for example, carry an internally generated, monotonically increasing read
round/id in heartbeat `Context` (the code comment at `raft.go:831-833`
already suggests "an interally defined context instead of the user given
context"), or record the heartbeat round at registration and ignore responses
from earlier rounds. Alternatively reject/serialize reuse of a context within
a term. Keep the update's freeing of released entries.
