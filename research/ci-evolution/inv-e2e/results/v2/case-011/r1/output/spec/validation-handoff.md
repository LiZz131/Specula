# Validation handoff (incremental, Pre-Vote revision)

- **Source**: `artifact/` at commit `3ab6cddc34a5bf127747434bb41e20a1b9ef7769` (`update`), parent `1adc857` (`baseline`).
  Test-only instrumentation is applied on top (`harness/apply-instrumentation.sh`; diff in
  `harness/instrumentation.patch` and `harness/patches/memstore-delay-save-vote.patch`).
- **Toolchain**: installed `stable` (cargo 1.100.0); the pinned `nightly-2026-03-01` is not installed and
  `/opt/rustup` is read-only (the prior run used `nightly-2025-12-31`, also unavailable now).
- **Harness command**: `bash harness/run.sh` (apply, build, 16 scenarios, 2 code observations) then
  `bash harness/validate-traces.sh` (TLC replay, `TraceConsumed`).
- **Fresh traces** (`traces/`, all regenerated on the new revision):
  - prior scenarios (rebased, same setup): `start_election`, `reject_stale_log`, `grant_greater_vote`,
    `establish_leader`, `append_joint_membership`, `commit_membership`, `restart_follower`;
  - update scenarios: `prevote_timer_multi`, `prevote_external_single_voter`, `prevote_req_reject_lease`,
    `prevote_req_reject_log`, `prevote_req_grant`, `prevote_resp_reject_then_quorum` (3 events),
    `prevote_cancelled_by_vote_grant` (2), `prevote_stale_round_after_leadership` (3),
    `prevote_round_reuses_probe` (4).
- **Outcome**: 16/16 PASS with `TraceConsumed`, pre- and post-state checks on every event
  (`spec/output/trace-validation-summary.txt`, per-trace logs `spec/output/trace-<case>.log`); field
  consumption audit `spec/output/trace-field-consumption.txt`.
- **Affected-action coverage**: `TickPreElect`, `ExternalPreElect` (self-quorum and multi-voter),
  `HandlePreVoteRequest` (lease reject, log reject, grant), `HandlePreVoteResponse` (reject + greater log,
  grant, quorum → elect), `ElectEffects` via quorum, cancellation by `HandleVoteRequest` and
  `HandleAppendEntries`, `HandleVoteResponse` win with a live pre-candidate. Interaction U2 observed in
  `prevote_stale_round_after_leadership`; U4 probe reuse observed in `prevote_round_reuses_probe`.
- **Not trace-covered (documented gaps)**: RaftCore leader-id correlation and RPC timeout (code review + model
  + end-to-end reproductions), default-network fallback grant (`PreVoteFallbackPeers`), `RefreshServerState`
  and `Restart` clearing a live pre-candidate, runtime toggle of `enable_pre_vote`.
- **Archived old-version traces**: the 7 prior traces remain immutable in
  `/work/previous/.specula-output/traces/`; each is superseded by the fresh new-version trace of the same
  scenario (no scenario removed).
- **Semantic spec files changed during validation**: yes — `HandleVoteResponse` lease repair (Round 1),
  `LogLE` repair and `PreElect` RPC-timeout drop (Round 2). The full trace suite was re-validated after the
  last change.
