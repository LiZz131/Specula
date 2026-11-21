# Validation changelog

Prior V0 history (exact-old run, unchanged) is preserved at
`/work/previous/.specula-output/spec/changelog.md`. V0 logs seeded into this run
were moved to `spec/output/archive-v0/`.

## V1 incremental run — source identity

- Old: neutral commit `baseline` 7289d1c5e049933b90a9692bbf508714bee02fce
  (`read_only.go` sha256 prefix f56e53c4…, matches `/work/old-source`).
- New: neutral commit `update` c780d355cfeae6ee6be52c50c1f0bd7d30c6657a
  (`read_only.go` cc2eac3a…, `raft_test.go` 3aec8b77…, match `/work/new-source`).
- Source delta: `read_only.go:103` delete key `rs.req.Context` ->
  `rs.req.Entries[0].Data`; new test `TestRaftFreesReadOnlyMem`.
- Disposition (Chapter 1): **MODEL_CHANGE_REQUIRED** (`analysis-report.md` §V1).

## V1 Round 1 — Generation

- [update] `HandleHeartbeatResponse`: released FIFO prefix contexts are deleted
  from `pendingReads` (read_only.go:100-105). V0 deliberately kept them.
- [update] `ProcessReadIndex`: unchanged guard text, but the duplicate guard
  (read_only.go:54-56) now admits a context whose earlier request was released.
- [repair, source unchanged] `raft.reset` installs a new `readOnly`
  (raft.go:489-511): read state now cleared in `Campaign`, `BecomeLeader`,
  `HandleVoteRequest` (higher term), `HandleAppendEntries`/`HandleHeartbeat`
  (higher term or same-term candidate), `CheckQuorum` step-down. V0 kept read
  state across these transitions.
- [repair, source unchanged] `BecomeLeader`: rebuild progress (peers Match 0,
  Next lastIndex+1; self Match lastIndex), clear votes and RecentActive
  (raft.go:501-508). V0 kept stale `matchIndex` from an earlier leadership,
  which can feed `CommitCandidate`.
- [repair] `HandleReadIndexResponse`: justification looked up in the ghost
  release history; V0 read the leader's stale pending entry, which the update
  now deletes.
- [ghost] `readInc`, `readReleases`, pending `inc/bound/freshAcks`,
  `Msg.rinc` — evidence only; no guard reads them.
- [new] `UpdateProps.tla` (update properties/canaries), `Update.tla`
  (Affected/Interaction Actions, EnvUpdate, discharge), Update cfgs.

## V1 Round 1 — Harness rebase and trace validation

- [rebase] V0 `instrumentation.patch` applied cleanly to the updated tree (no
  drift in `raft.go`/`node.go`). Harness now materializes a clean copy of the
  `update` commit via `git archive`; the artifact is never modified.
- [densify] New probes: `HandleReadIndexRequest` (leader, remote origin),
  `ForwardReadIndex`, `HandleReadIndexResponse`, `BroadcastHeartbeat` (MsgBeat).
  New mandatory state fields `pendingCtxs` and `readStates[{index,ctx}]`.
- [fix-capture] MsgReadIndex/MsgReadIndexResp context comes from
  `Entries[0].Data`, not the log-value field.
- [trace] New scenarios: `read_reuse`, `forwarded_read`, `delayed_ack`,
  `step_down_reads`, `higher_term_reads` (+ prior `quorum_read`, `quorum_loss`
  rerun on the new code).
- [pass] All 7 fresh traces replay with `TraceMatched`, post-state checks and
  safety/update invariants (first-try pass after the generation edits).
- [witness] `delayed_ack` replay violates `UpdReadAckAfterEnqueue` — the real
  updated implementation counted a response generated before the context was
  enqueued again.
- [discrimination] V0 model rejects fresh read traces at the first releasing
  heartbeat response (traceLine 26) and the repair traces at the reset events
  (27, 25); V1 model rejects the archived V0 `quorum_read` at 26.
  `spec/discrimination/README.md`.

## V1 Round 1 — Model checking

- [fix-inv, Case A] `UpdReadAckFreshness` (r1: acks must answer heartbeats
  *sent* for the pending incarnation) was violated by an interleaving where a
  first-round heartbeat reached s3 only after the context was re-enqueued; the
  response is generated after acceptance and confirms leadership, and the
  implementation correlates acknowledgements only by context. Revised to
  `UpdReadAckAfterEnqueue` (r2: responses generated after acceptance). The
  ghost tag moved from heartbeat to response. r1 logs kept as
  `output/superseded-*-r1.*`. Full fresh trace replay re-run: all pass.
- [bug-candidate, Case C pending confirmation] MC-1 `UpdReadAckAfterEnqueue`:
  `MC_hunt_s6_stale_ack.cfg`, 22 states (`output/hunt-s6-stale-ack.*`).
- [config] `MC.cfg` MaxReadyLimit 3 -> 6, MaxReadLimit 1 -> 2: with the
  persist-before-send contract the V0 standard config could not commit an
  entry (4 Ready publications needed), so reads were unreachable there.
- [fix-spec, Case B, V0 defect, not update-related] `Crash`: `Update_focused_nk.cfg`
  reported `MCLeaderCompleteness` (21 states,
  `output/superseded-update-focused-nk-precrashfix.*`): s2 appended the leader's
  entry and emitted `MsgAppResp`, crashed before persisting, restarted, became
  term-2 leader without the entry; the pre-crash response was delivered later
  because the length-only gate was satisfied by s2's *term-2* durable entry, and
  s1 committed an entry no quorum durably held. Real code keeps unsent messages
  in volatile `r.msgs` and transmits them only after the Ready that carries
  them is persisted (node.go:58-85), so the crash loses that response. Repair:
  `Crash(i)` drops i's in-flight messages not justified by its durable state
  (`PublishedBySender`). Trace regression re-run: all 8 fresh traces pass.
  Runs started before this fix with crash budget > 0 (`mc-standard`,
  `update-full-nk`, `update-discharge`, `update-open`, `hunt-s1/s2`) are
  rerun or recorded as pre-fix (see campaign summary).
- [search] `VIEW MCView` drops fault counters (inherited V0 design); a bounded
  BFS can then keep a state reached with more counter usage and miss paths that
  need the remaining budget. `diag/PathCheck.tla` (diagnostic only) drives
  MCSpec along a 38-step S6b schedule and TLC reports
  `UpdReadIndexLinearizable` violated, so the miss in
  `superseded-hunt-s6-linearizable-guided-viewmasked.log` was a search
  artifact; guided hunts now run without the VIEW. Results of VIEW-based runs
  remain LIMITED_COVERAGE, including "exhausted" ones.

## V1 Result

- Generation: MODEL_CHANGE_REQUIRED; reference updated (delete on release),
  three V0 defects repaired (reset read state, leader progress reset, forwarded
  justification lookup) plus the Crash repair found in model checking.
- Validation: 8 fresh traces from the updated implementation, all pass with
  TraceMatched on the final candidate; 2 real-execution property witnesses
  (`delayed_ack`: UpdReadAckAfterEnqueue; `stale_read_reuse`:
  UpdReadIndexLinearizable). Archived V0 `quorum_read` superseded.
- Model checking: one update-attributed Case C candidate, MC-1 (stale ReadIndex
  after context reuse), counterexamples in 21/22/37 states; all other
  campaigns budget-limited without violation (LIMITED_COVERAGE), reachability
  canaries all witnessed. `output/campaign-summary.md`.
