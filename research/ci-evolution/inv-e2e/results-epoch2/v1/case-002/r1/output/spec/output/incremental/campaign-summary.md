# V1 model-checking campaign summary (generated from runs/ledger.ndjson)

Exit 12 = invariant/property violation (counterexample in log). Exit 0 with a nonzero queue (or a simulation) = stopped by its time budget: LIMITED_COVERAGE, not a pass. Exit 0 with queue 0 = the configured finite, depth-bounded (and, for MC-filtered, MC-2-filtered) space was exhausted: still finite-bound evidence, not a proof. `mc-standard-filtered-sim` ran with the round-1 filter (`FilterKnownU4Flushed`); `mc-standard-filtered2-bfs` with the final `FilterKnownU4`.

| id | module | cfg | mode | exit | violated | distinct | generated | queue | depth | log |
|---|---|---|---|---|---|---|---|---|---|---|
| hunt2s-CertifiedDurableOnQuorum-bfs | Update.tla | Update-hunt2s-CertifiedDurableOnQuorum.cfg | bfs | 12 | CertifiedDurableOnQuorum | 14192 | 45490 | 3106 | 28 | spec/output/incremental/runs/hunt2s-CertifiedDurableOnQuorum-bfs.log |
| upd-focused-P1-bfs | Update.tla | Update-focused-P1.cfg | bfs | 12 | NewLeaderAckImpliesDurableSync | 1188657 | 5727278 | 439821 | 21 | spec/output/incremental/runs/upd-focused-P1-bfs.log |
| upd-full-P1-bfs | Update.tla | Update-full-P1.cfg | bfs | 12 | NewLeaderAckImpliesDurableSync | 1441620 | 6901136 | 561223 | 21 | spec/output/incremental/runs/upd-full-P1-bfs.log |
| mc-standard-bfs | MC.tla | MC.cfg | bfs | 12 | PipelinePrefix | 3330700 | 15851266 | 1269775 | 23 | spec/output/incremental/runs/mc-standard-bfs.log |
| mc-standard-filtered-sim | MCFiltered.tla | MC-filtered.cfg | simulation | 0 | - | - | 81778429 | - | - | spec/output/incremental/runs/mc-standard-filtered-sim.log |
| hunt2s-NewLeaderAckIsFirstAck-bfs | Update.tla | Update-hunt2s-NewLeaderAckIsFirstAck.cfg | bfs | 12 | NewLeaderAckIsFirstAck | 3324 | 10059 | 700 | 23 | spec/output/incremental/runs/hunt2s-NewLeaderAckIsFirstAck-bfs.log |
| hunt2s-VotingHistoryCoversDurable-bfs | Update.tla | Update-hunt2s-VotingHistoryCoversDurable.cfg | bfs | 12 | VotingHistoryCoversDurable | 2644 | 7890 | 575 | 23 | spec/output/incremental/runs/hunt2s-VotingHistoryCoversDurable-bfs.log |
| huntU1-P3-bfs | HuntU1.tla | HuntU1-P3.cfg | bfs | 12 | CertifiedRetainedByLaterLeaders | 1539278 | 8844423 | 566717 | 41 | spec/output/incremental/runs/huntU1-P3-bfs.log |
| upd-focused-P2-bfs | Update.tla | Update-focused-P2.cfg | bfs | 12 | PipelinePrefix | 3171549 | 15250988 | 1110194 | 23 | spec/output/incremental/runs/upd-focused-P2-bfs.log |
| upd-full-P2-bfs | Update.tla | Update-full-P2.cfg | bfs | 12 | PipelinePrefix | 3427966 | 16638813 | 1296879 | 22 | spec/output/incremental/runs/upd-full-P2-bfs.log |
| huntU1-P3-crash-bfs | HuntU1.tla | HuntU1-P3-crash.cfg | bfs | 12 | CertifiedRetainedByLaterLeaders | 999876 | 4937617 | 357604 | 43 | spec/output/incremental/runs/huntU1-P3-crash-bfs.log |
| upd-discharge-bfs | Update.tla | Update-discharge.cfg | bfs | 0 | - | 7376979 | 35904306 | 2767734 | 25 | spec/output/incremental/runs/upd-discharge-bfs.log |
| mc-standard-filtered-bfs | MCFiltered.tla | MC-filtered.cfg | bfs | 12 | PipelinePrefix | 5545313 | 41833858 | 222451 | 23 | spec/output/incremental/runs/mc-standard-filtered-bfs.log |
| upd-focused-P4-bfs | Update.tla | Update-focused-P4.cfg | bfs | 12 | NewLeaderAckIsFirstAck | 1951697 | 9442289 | 699290 | 22 | spec/output/incremental/runs/upd-focused-P4-bfs.log |
| upd-full-P4-bfs | Update.tla | Update-full-P4.cfg | bfs | 12 | NewLeaderAckIsFirstAck | 1954362 | 9331050 | 757211 | 22 | spec/output/incremental/runs/upd-full-P4-bfs.log |
| upd-focused-P5-bfs | Update.tla | Update-focused-P5.cfg | bfs | 12 | VotingHistoryCoversDurable | 1150779 | 5533990 | 429171 | 21 | spec/output/incremental/runs/upd-focused-P5-bfs.log |
| upd-full-P5-bfs | Update.tla | Update-full-P5.cfg | bfs | 12 | VotingHistoryCoversDurable | 1404515 | 6711879 | 548653 | 21 | spec/output/incremental/runs/upd-full-P5-bfs.log |
| upd-focused-P3-bfs | Update.tla | Update-focused-P3.cfg | bfs | 12 | PipelinePrefix | 7007713 | 36940111 | 2729717 | 23 | spec/output/incremental/runs/upd-focused-P3-bfs.log |
| upd-full-P3-bfs | Update.tla | Update-full-P3.cfg | bfs | 12 | PipelinePrefix | 7438727 | 38752451 | 3036892 | 23 | spec/output/incremental/runs/upd-full-P3-bfs.log |
| upd-open-bfs | Update.tla | Update-open.cfg | bfs | 75 | - | 41 | 122 | 33 | 5 | spec/output/incremental/runs/upd-open-bfs.log |
| upd-full-P2-sim | Update.tla | Update-full-P2.cfg | simulation | 12 | CertifiedDurableOnQuorum | - | 11273448 | - | - | spec/output/incremental/runs/upd-full-P2-sim.log |
| upd-open-smoke | Update.tla | Update-open.cfg | bfs | 12 | NewLeaderAckImpliesDurableSync | 1189474 | 8358651 | 452089 | 22 | spec/output/incremental/runs/upd-open-smoke.log |
| upd-full-P3-sim | Update.tla | Update-full-P3.cfg | simulation | 0 | - | - | 32159300 | - | - | spec/output/incremental/runs/upd-full-P3-sim.log |
| upd-full-P2-filtered-bfs | UpdateFiltered.tla | Update-full-P2-filtered.cfg | bfs | 0 | - | 10576692 | 51847498 | 3939965 | 26 | spec/output/incremental/runs/upd-full-P2-filtered-bfs.log |
| upd-focused-P2-filtered-bfs | UpdateFiltered.tla | Update-focused-P2-filtered.cfg | bfs | 0 | - | 10415297 | 50901060 | 3413136 | 26 | spec/output/incremental/runs/upd-focused-P2-filtered-bfs.log |
| mc-standard-filtered2-bfs | MCFiltered.tla | MC-filtered.cfg | bfs | 0 | - | 5841254 | 45937512 | 0 | 23 | spec/output/incremental/runs/mc-standard-filtered2-bfs.log |
| base-bfs | base.tla | base.cfg | bfs | 12 | PipelinePrefix | 948777 | 6142471 | 243636 | 23 | spec/output/incremental/runs/base-bfs.log |
| v0-hunt-election | MC.tla | MC-hunt-election.cfg | bfs | 12 | NotElectionReached | 35 | 141 | 5 | 6 | spec/output/incremental/runs/v0-hunt-election.log |
| v0-hunt-mutation | MC.tla | MC-hunt-mutation.cfg | bfs | 12 | NotMutationReached | 1451 | 2278 | 50 | 24 | spec/output/incremental/runs/v0-hunt-mutation.log |
| v0-hunt-recovery | MC.tla | MC-hunt-recovery.cfg | bfs | 12 | NotRecoveryReached | 72 | 236 | 30 | 5 | spec/output/incremental/runs/v0-hunt-recovery.log |
| v0-hunt-sync | MC.tla | MC-hunt-sync.cfg | bfs | 12 | NotSyncReached | 109 | 314 | 8 | 11 | spec/output/incremental/runs/v0-hunt-sync.log |
| canary-NotUpToDateReached | Update.tla | Update-canary-NotUpToDateReached.cfg | bfs | 12 | NotUpToDateReached | 62344 | 312440 | 25057 | 15 | spec/output/incremental/runs/canary-NotUpToDateReached.log |
| canary-NotNonDurableNewLeaderAckReached | Update.tla | Update-canary-NotNonDurableNewLeaderAckReached.cfg | bfs | 12 | NotNonDurableNewLeaderAckReached | 1063466 | 5074543 | 389889 | 21 | spec/output/incremental/runs/canary-NotNonDurableNewLeaderAckReached.log |
| canary-NotAckShadowReached | Update.tla | Update-canary-NotAckShadowReached.cfg | bfs | 12 | NotAckShadowReached | 1642813 | 7860522 | 587382 | 21 | spec/output/incremental/runs/canary-NotAckShadowReached.log |
| upd-full-P4-sim | Update.tla | Update-full-P4.cfg | simulation | 12 | NewLeaderAckIsFirstAck | - | 4853 | - | - | spec/output/incremental/runs/upd-full-P4-sim.log |
| upd-full-P5-sim | Update.tla | Update-full-P5.cfg | simulation | 12 | VotingHistoryCoversDurable | - | 6569455 | - | - | spec/output/incremental/runs/upd-full-P5-sim.log |
| canary-NotInitialExitFlushedReached | Update.tla | Update-canary-NotInitialExitFlushedReached.cfg | bfs | 12 | NotInitialExitFlushedReached | 1081546 | 5090282 | 401513 | 21 | spec/output/incremental/runs/canary-NotInitialExitFlushedReached.log |
| canary-NotCertifiedLossReached | HuntU1.tla | HuntU1-canary-certloss.cfg | bfs | 12 | NotCertifiedLossReached | 1488729 | 8484709 | 556851 | 39 | spec/output/incremental/runs/canary-NotCertifiedLossReached.log |
| upd-full-P3-filtered-bfs | UpdateFiltered.tla | Update-full-P3-filtered.cfg | bfs | 0 | - | 16105999 | 85659007 | 6413455 | 25 | spec/output/incremental/runs/upd-full-P3-filtered-bfs.log |
| upd-focused-P3-filtered-bfs | UpdateFiltered.tla | Update-focused-P3-filtered.cfg | bfs | 0 | - | 16626854 | 88697643 | 6220891 | 25 | spec/output/incremental/runs/upd-focused-P3-filtered-bfs.log |
| upd-open-bfs-v2 | Update.tla | Update-open.cfg | bfs | 12 | NewLeaderAckImpliesDurableSync | 1207317 | 8609737 | 451860 | 20 | spec/output/incremental/runs/upd-open-bfs-v2.log |
| upd-focused-P2-filtered-sim | UpdateFiltered.tla | Update-focused-P2-filtered.cfg | simulation | 12 | CertifiedDurableOnQuorum | - | 26020428 | - | - | spec/output/incremental/runs/upd-focused-P2-filtered-sim.log |
| upd-discharge-bfs-v2 | Update.tla | Update-discharge.cfg | bfs | 0 | - | 13670163 | 66869740 | 5153167 | 26 | spec/output/incremental/runs/upd-discharge-bfs-v2.log |
| upd-focused-P3-filtered-sim | UpdateFiltered.tla | Update-focused-P3-filtered.cfg | simulation | 0 | - | - | 45294309 | - | - | spec/output/incremental/runs/upd-focused-P3-filtered-sim.log |
