# Validation changelog

(V0 rounds below the V1 section are the immutable prior history.)

## Round 1 — Trace validation

- [fix-spec] `HandleAppendEntries`: represented zero-entry Append messages so
  the exact-old leader commit broadcasts replay faithfully, in addition to the
  bounded one-entry append case.
- [fix-trace] State capture: encoded empty read queues as `[]` instead of JSON
  null so the sequence mapping is total.
- [pass] `quorum_read.ndjson`: all 28 records consumed; 29 distinct states.
- [pass] `quorum_loss.ndjson`: all 15 records consumed; 16 distinct states.
  `TraceMatched` and all enabled safety invariants held for both traces.

## Round 1 — Model checking

- [fix-config] Symmetry: changed MC constants from strings to model values so
  `Permutations(Server)` is valid. Trace constants remain exact Go strings.
- [fix-spec] Ready publication contract (Case B): gated ordinary message
  delivery on sender-side durable HardState/log. This removed an impossible
  pre-persistence crash/restart election counterexample without changing
  `ElectionSafety`.
- [fix-config] Disabled deadlock checking for counter-bounded terminal states;
  safety invariant checking remains enabled.

## Round 2 — Convergence and coverage

- [pass] Revalidated the final trace adapter after model changes.
- [pass] Exhausted `MC_complete_core.cfg`, `MC_hunt_s1_election.cfg`, and
  `MC_hunt_s3_quorum.cfg` without a neutral invariant violation.
- [coverage] Preserved timeout-bounded main, replication, and ReadIndex logs.
- [coverage] Split expected reachability violations into `Reach_*.cfg` and
  `reach-*.log`, separate from safety hunting results.

## Result

Trace validation passed for both collected executions. Bounded model checking
found zero model-checking bugs; overall coverage remains limited by explicit
state, action, environment, and timeout bounds.

# V1 — incremental run for the `update` revision

## Generation (Round V1-G)

- [update] `HandleHeartbeatResponse`: released requests are deleted from
  `pendingReads` (read_only.go:100-104); late acks for released contexts are
  ignored (read_only.go:64-68). Source-driven.
- [repair] readOnly `reset()` (raft.go:489-511) now clears `pendingReads`/
  `readQueue` in `Campaign`, `BecomeLeader`, higher-term or same-term-candidate
  `HandleVoteRequest`/`HandleAppendEntries`/`HandleHeartbeat`, `CheckQuorum`
  step-down, and higher-term `HandleReadIndexResponse`. Pre-existing V0 defect.
- [repair] `HandleReadIndexResponse` follows Step term/role rules
  (raft.go:679-734, 1075-1080) and takes justification from the ghost release
  log `readReleases` instead of the leader's live pending map. Pre-existing V0
  defect exposed by the update.
- [ghost] `floor`, `fresh`, `readReleases`, scenario flags; no enabledness effect.
- [props] Update.tla/UpdateProps.tla: `PendingMatchesQueue`, `ReadQueueDistinct`
  (added), `ReadDeliveryJustifiedFresh` (revision of `ReadDeliveryJustified`,
  strengthening), `ReadIndexFreshness` (added). Evidence in
  `spec/invariant-evidence.json`. No property weakened.
- Preflight: SANY on all modules (`spec/output/generation/`), static
  variable-assignment and cfg-name resolution (`static-preflight.log`; the two
  flagged tokens are inside comments).

## Validation (Round V1-T)

- [harness] Prior patch applied to the update tree without drift; `apply.sh`
  rebased to export a commit of the artifact repository; added
  `ForwardReadIndex`/`HandleReadIndexResponse` probes and read-message ctx
  capture; three update scenarios; standalone reproduction test.
- [pass] Fresh new-revision traces, first attempt, no spec/trace repair needed:
  `quorum_read` 28 rec / 29 states, `quorum_loss` 15/16, `read_reuse` 28/29,
  `stale_read` 33/34, `read_stepdown` 35/36; all records consumed,
  `TraceMatched` checked, all safety + `PendingMatchesQueue`/`ReadQueueDistinct`
  invariants held (`spec/output/trace/*.log`).
- [sensitivity] V0 model on fresh traces fails at the release (quorum_read
  record 26, pendingCount) and at the step-down reset (read_stepdown record 16);
  V1 model on fresh old-revision traces fails at the same release points;
  V1 with only the reset repair reverted fails read_stepdown record 16
  (`spec/evidence/v0-on-new`, `v1-on-old`, `v1-noreset`).
- [observation] `ReadDeliveryJustifiedFresh` is violated on the replayed
  `read_reuse` and `stale_read` traces and `ReadIndexFreshness` on
  `stale_read`; the V0 `ReadDeliveryJustified` holds on both
  (`spec/evidence/Eval_*.log`). Recorded as bug candidates, not property edits.
- [archived] `traces/archive-v0/*.ndjson` (V0, old revision) retained as
  superseded evidence: they encode the stale pending entry removed by the update.

## Model checking (Round V1-M)

- [pass] `MC.cfg` (standard round) exhausted: 22,496,273 generated /
  4,291,336 distinct, 0 left on queue, no violation (`spec/output/mc/mc_standard.log`).
- [bug] `HandleHeartbeatResponse` (US3, Case C): `ReadDeliveryJustifiedFresh`
  violated in `Update_focused.cfg` (22 states) and `Update_focused_reset.cfg`
  (21 states, MsgBeat variant): an ack produced before the same context was
  enqueued again releases the new request. Matches fresh trace `read_reuse`.
- [bug] same root cause (US4, Case C): `ReadIndexFreshness` violated in
  `Update_hunt_us4_guided.cfg` (37 states, full MCSpec + search-pruning
  constraint): stale ReadState below an index committed by the newer leader.
  Matches fresh trace `stale_read` and the reproduction test.
- [fix-spec] `HandleReadIndexResponse` ghost justification (Case B, my V1 draft):
  simulation `sim_us4_full` reported `MCReadDeliveryJustified` after two
  justified releases of the same forwarded context produced identical
  responses; the draft intersected acks across both release records, inventing
  evidence `{s1}`. Now the ghost picks one matching release per delivery
  (existential, no field mixing). Ghost-only: reachable real states unchanged,
  and every property is monotone in the changed ghost fields, so passing results
  remain sound; affected campaigns are rerun on the final artifacts anyway.
  Local feedback: full fresh-trace regression re-passed (5/5).
- [rerun] Final artifacts: `MC.cfg` re-EXHAUSTED with identical counts; US3/US4
  counterexamples regenerated (`final_update_focused` 22 states,
  `final_update_focused_reset` 21, `final_hunt_us4_guided` 37); `Update_full`,
  `Update_open`, `Update_discharge` reran without violation (LIMITED_COVERAGE);
  unguided simulation `sim_update_full` independently found US3 (44 states,
  forwarded reads from two followers sharing a context).
- [control] `DischargeNegativeControl` refuted (non-vacuous discharge).
- [coverage] Inherited hunts/canaries rerun on the V1 suite; all canaries reached.

## Result (V1)

Converged: fresh new-revision traces 5/5 PASS on the final model; no open Case
A/B. Model checking: 1 bug (MC-1, Case C, reproduced on the update revision,
absent on the baseline). Coverage limits as recorded in
`spec/output/mc/campaigns.md` (time-budgeted runs are LIMITED_COVERAGE).
