# Model-checking summary (run incr-8c80add29fe2)

Generated from `spec/output/incr/command-results.ndjson` (latest record per run id; superseded runs are kept as
`*-r1-pre-discovery-guard.log` / `*-attempt1-*.log`). Bounded explorations are LIMITED_COVERAGE, never proofs.

| Run | Spec / cfg | Distinct states | Left on queue | Depth | Outcome | Log |
|---|---|---:|---:|---:|---|---|
| canary-seed | Update.tla / Update-seed-canary.cfg | 276794 | 124356 | 18 | Invariant NotUpdateSeed is violated | spec/output/incr/canary-seed.log |
| canary-diff-window | Update.tla / Update-canary-diffwindow.cfg | 614279 | 254986 | 20 | Invariant NotDiffHandoffReached is violated | spec/output/incr/canary-diff-window.log |
| canary-newleader-ack | Update.tla / Update-canary-handoff.cfg | 18652 | 8581 | 14 | Invariant NotNewLeaderAckReached is violated | spec/output/incr/canary-newleader-ack.log |
| mc-standard | MC.tla / MC.cfg | 23,175,680 | 2,944,668 | 23 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/mc-standard.log |
| seed-focused-U1U3 | UpdateSeed.tla / Update-seed-focused-U1U3.cfg | 8991271 | 2957600 | 23 | Invariant CommittedSurvivesLeaderChange is violated | spec/output/incr/seed-focused-U1U3.log |
| seed-focused-U2 | UpdateSeed.tla / Update-seed-focused-U2.cfg | 12433 | 5587 | 10 | Invariant NewLeaderAckDurable is violated | spec/output/incr/seed-focused-U2.log |
| seed-oldcontrol-U1 | UpdateSeed.tla / Update-seed-oldcontrol-U1.cfg | 12370 | 5567 | 10 | Invariant AckedHistoryHandedOff is violated | spec/output/incr/seed-oldcontrol-U1.log |
| hunt-election | MC.tla / MC-hunt-election.cfg | 24 | 10 | 4 | Invariant NotElectionReached is violated | spec/output/incr/hunt-election.log |
| hunt-mutation | MC.tla / MC-hunt-mutation.cfg | 11821 | 1598 | 22 | Invariant NotMutationReached is violated | spec/output/incr/hunt-mutation.log |
| hunt-recovery | MC.tla / MC-hunt-recovery.cfg | 48 | 33 | 4 | Invariant NotRecoveryReached is violated | spec/output/incr/hunt-recovery.log |
| hunt-sync | MC.tla / MC-hunt-sync.cfg | 104 | 16 | 9 | Invariant NotSyncReached is violated | spec/output/incr/hunt-sync.log |
| seed-fixedcontrol | UpdateSeed.tla / Update-seed-fixedcontrol.cfg | 22,660,118 | 6,359,391 | 26 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/seed-fixedcontrol.log |
| seed-oldcontrol-U3 | UpdateSeed.tla / Update-seed-oldcontrol-U3.cfg | 7012844 | 2269705 | 23 | Invariant CommittedSurvivesLeaderChange is violated | spec/output/incr/seed-oldcontrol-U3.log |
| seed-focused-U1 | UpdateSeed.tla / Update-seed-focused-U1.cfg | 24,541,619 | 7,009,771 | 26 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/seed-focused-U1.log |
| final-trace-follower-diff | Trace.tla / Trace.cfg | 18 | 0 | 18 | no violation; search exhausted within the configured bound | spec/output/incr/final-trace-follower-diff.log |
| final-trace-follower-snap | Trace.tla / Trace.cfg | 19 | 0 | 19 | no violation; search exhausted within the configured bound | spec/output/incr/final-trace-follower-snap.log |
| final-trace-quorum-startup-mutation-shutdown | Trace.tla / Trace.cfg | 73 | 0 | 73 | no violation; search exhausted within the configured bound | spec/output/incr/final-trace-quorum-startup-mutation-shutdown.log |
| final-trace-leader-abandon-restart-recovery | Trace.tla / Trace.cfg | 272 | 0 | 272 | no violation; search exhausted within the configured bound | spec/output/incr/final-trace-leader-abandon-restart-recovery.log |
| final-trace-diff-sync-consistency | Trace.tla / Trace.cfg | 126 | 0 | 126 | no violation; search exhausted within the configured bound | spec/output/incr/final-trace-diff-sync-consistency.log |
| final-control-oldtrace-newsemantics | Trace.tla / Trace.cfg | 9 | 0 | 9 | Temporal property TraceMatched was violated | spec/output/incr/final-control-oldtrace-newsemantics.log |
| final-control-oldtrace-oldsemantics | Trace.tla / Trace-oldcontrol.cfg | 18 | 0 | 18 | no violation; search exhausted within the configured bound | spec/output/incr/final-control-oldtrace-oldsemantics.log |
| seed-full-U1U3 | UpdateSeed.tla / Update-seed-full-U1U3.cfg | 23738797 | 8449364 | 25 | Invariant CommittedSurvivesLeaderChange is violated | spec/output/incr/seed-full-U1U3.log |
| update-full-U1U3 | Update.tla / Update-full-U1U3.cfg | 33,195,070 | 14,152,540 | 23 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/update-full-U1U3.log |
| mc-standard-sim | MC.tla / MC-sim.cfg | 70025406 checked (sim) | 1166179 traces | mean 42 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/mc-standard-sim.log |
| update-focused | Update.tla / Update-focused.cfg | 27,062,915 | 10,319,421 | 23 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/update-focused.log |
| update-full-U2 | Update.tla / Update-full-U2.cfg | 30,554,823 | 13,074,083 | 23 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/update-full-U2.log |
| update-full-U1U3-sim | Update.tla / Update-full-U1U3-sim.cfg | 159328999 checked (sim) | 2275698 traces | mean 43 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/update-full-U1U3-sim.log |
| update-full-U2-sim | Update.tla / Update-full-U2-sim.cfg | 239614768 checked (sim) | 3422419 traces | mean 40 | no violation; stopped at time budget (LIMITED_COVERAGE) | spec/output/incr/update-full-U2-sim.log |

## Campaign map (incremental order)

| Step | Runs | Outcome |
|---|---|---|
| Entry gate | 5/5 fresh traces (`final-trace-*`) | pass |
| Standard MC round | `mc-standard` (BFS, depth-23 bound), `mc-standard-sim` | no violation; budget-limited |
| 1. Full update check (MCNext) | `update-full-U1U3`, `update-full-U2` (+ `-sim`) from `MCInit`; `seed-full-U1U3` from the MC-reached seed | from Init: no violation within budget (U2/U3 witnesses need depth 25/38); from seed: U3 violated (MC-1) |
| 2. Concrete focused | `update-focused` (from Init), `seed-focused-U2`, `seed-focused-U1U3`, `seed-focused-U1` | U2 and U3 violated (MC-1); U1 holds within bound |
| 3. Open / discharge | none | not applicable: `Update.tla` defines no `EnvUpdate`; every focused relation is a restriction of `MCNext` |
| 4. Scenario hunts / canaries | `hunt-*`, `canary-*` | every reachability canary violated as expected (witnesses) |
| Controls | `seed-oldcontrol-U1`, `seed-oldcontrol-U3`, `seed-fixedcontrol` | old behaviour violates U1 and U3 (U3 without crash); hypothetical flush-before-ACK: no U2/U3 violation to depth 26 (budget-limited) |
| 5. Final full check | all of the above re-run after the last semantic repair (discovery guard) | as listed |

Superseded first-round runs (before the `FinishDiscovery` guard repair) are preserved as
`output/incr/*-r1-pre-discovery-guard.log`; runs aborted by a frame-condition error as `*-attempt1-*.log`.
