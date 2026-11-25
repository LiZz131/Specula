# Final campaign outcomes (final artifacts, `final-candidate-sha256.txt`)

All BFS runs use a planned `-Dtlc2.TLC.stopAfter` limit; a non-empty queue means **LIMITED_COVERAGE** (budget-limited exploration, not exhaustive, not a proof). TLC state under `/dev/shm/specula-e2e-case-002` (removed after each run).

| Run (log `mc-<run>.log`) | Config | Purpose | Mode | Result | Generated | Distinct | Queue left | Depth / traces |
|---|---|---|---|---|---:|---:|---:|---|
| final-std-mc-bfs | `MC.cfg` | standard convergence (reference invariants + temporal), MCInit | bfs | no violation (budget-limited) | 75174046 | 16161867 | 6051487 | 28 |
| final-update-full-bfs | `Update-full.cfg` | full update check, all U1-U4 over MCNext from MCInit | bfs | no violation (budget-limited) | 18017594 | 3214414 | 1231531 | 22 |
| final-update-full-sim | `Update-full.cfg` | full update check, simulation depth 60 | sim | VIOLATION NewLeaderAckImpliesDurable | 61759 | - | - |  / 1030 traces |
| final-full-compl-sim | `Update-full-completeness.cfg` | full MCNext from MCInit, U1/U2 + reference, simulation depth 70 | sim | no violation in 280,024 random traces (budget-limited; the depth-43 U1 path from MCInit was not sampled) | 19576276 | - | - |  / 280024 traces |
| final-fullckpt-compl-bfs | `Update-full-checkpoint-completeness.cfg` | full MCNext from checkpoint, U1/U2 + reference | bfs | no violation (budget-limited) | 56089586 | 10908661 | 4094838 | 24 |
| final-focus-compl-bfs | `Update-focus-completeness.cfg` | concrete focused (Affected+Interaction) from checkpoint | bfs | no violation (budget-limited) | 57999413 | 11225025 | 4046622 | 24 |
| final-open-compl-bfs | `Update-open-completeness.cfg` | open focused (+EnvUpdate) from checkpoint | bfs | no violation (budget-limited) | 35790001 | 6931480 | 2608180 | 23 |
| final-discharge-bfs | `Update-discharge.cfg` | discharge: omitted DropMessage/TakeSnapshot satisfy EnvUpdateBase (full MCNext) | bfs | no violation (budget-limited) | 23897922 | 4962924 | 1942738 | 24 |
| final-hunt-reelection-bfs | `Update-hunt-reelection.cfg` | U-2 hunt (focused) | bfs | VIOLATION LeaderCompleteness | 5247144 | 1466793 | 288513 | 27 |
| final-hunt-reelection-fullnext-bfs | `Update-hunt-reelection-fullnext.cfg` | U-2 hunt (full MCNext) | bfs | VIOLATION LeaderCompleteness | 5439483 | 1520260 | 298251 | 28 |
| final-hunt-crash-window-bfs | `Update-hunt-crash-window.cfg` | U-1 hunt (focused) | bfs | VIOLATION LeaderCompleteness | 4808845 | 1334914 | 218615 | 29 |
| final-hunt-crash-window-fullnext-bfs | `Update-hunt-crash-window-fullnext.cfg` | U-1 hunt (full MCNext) | bfs | VIOLATION LeaderCompleteness | 5017724 | 1392042 | 223943 | 29 |
| final-focus-trunc-bfs | `Update-focus-trunc.cfg` | MC-3 recheck (reference invariants, no filter) | bfs | VIOLATION ServingApplyRequiresCommitCertificate | 23680 | 8596 | 2705 | 15 |
| final-canary-ack-window | `Update-hunt-ack-window.cfg` | canary U-1 | bfs | VIOLATION NotPendingLoggedAcked | 367395 | 75482 | 34044 | 13 |
| final-canary-uptodate | `Update-hunt-uptodate.cfg` | canary U-3 | bfs | VIOLATION NotUptodateAfterLogging | 685259 | 143937 | 59291 | 15 |
| final-canary-skipped-shutdown | `Update-hunt-skipped-shutdown.cfg` | canary U-2 | bfs | VIOLATION NotSkippedShutdownAfterAck | 234306 | 50538 | 22263 | 13 |
| final-canary-inherited-election | `MC-hunt-election.cfg` | canary V0 S1 | bfs | VIOLATION NotElectionReached | 148 | 46 | 34 | 5 |
| final-canary-inherited-sync | `MC-hunt-sync.cfg` | canary V0 S2 | bfs | VIOLATION NotSyncReached | 14047 | 2728 | 1509 | 9 |
| final-canary-inherited-mutation-sim | `MC-hunt-mutation.cfg` | canary V0 S3 (simulation) | sim | VIOLATION NotMutationReached | 445 | - | - |  / 7 traces |
| final-canary-inherited-recovery | `MC-hunt-recovery.cfg` | canary V0 S4 | bfs | VIOLATION NotRecoveryReached | 198 | 57 | 41 | 5 |

Notes
- Focused/full hunts start from `FocusInit`, the final state of the 16-state witness
  `mc-checkpoint-witness-r2.log` reachable from `MCInit`; the `-fullnext` reruns show the U-1/U-2
  counterexamples are admitted by the complete `MCNext` (witness prefix + hunt trace is an
  `MCSpec` behaviour).
- `Update-*-completeness.cfg` disable the already analysed U3/U4 (they stop runs at depth
  13-15) and prune MC-3 states with `FilterTruncExtraEntry`; `MC.cfg` and
  `Update-focus-trunc.cfg` keep MC-3 observable.
- Superseded/aborted runs (before the vote-lifetime and fast-forward repairs) are kept with
  their logs (`mc-*-r1/-r2/-r3*`, `*-superseded-rely.log`) and are not counted as final
  evidence.
| final-focus-conseq-bfs | `Update-focus-consequence.cfg` | concrete focused, U4 enabled (U3 off) | bfs | VIOLATION AckedHistoryRetained | 700067 | 139529 | 59778 | 15 |
