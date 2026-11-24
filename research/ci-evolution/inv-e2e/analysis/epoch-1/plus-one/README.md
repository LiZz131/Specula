# Plus-one robustness experiment (inv-e2e, epoch 1)

Question: if every integer counting constant in a suite's own checking configs is raised by one and the
suite's own invariants/properties are re-checked, which new violations appear, and at what cost?

Scope: 3 arms (v0, v1, v2) × 7 cases (002, 003, 004, 006, 010, 011, 012), run `r1` only.
Inputs were only `results/<arm>/<case>/r1/output/spec/` (copied to `/mydata/bingzhuo/evidence-work/i5/<arm>/<case>/`).

## Method

1. **Copy.** Each `spec/` directory was copied to the work area; all runs used the copy.
2. **Cfg selection (mechanical, uniform across the 21 suites).** From the cfgs with INVARIANT/PROPERTY entries,
   reachability canaries/witnesses (Canary, Reach, NotReach, Witness), trace cfgs, hunt cfgs (guided by
   bug-directed constraints), discharge/negative-control/evidence/old-control cfgs were skipped. Per suite we kept:
   - `MC.cfg` (the standard convergence config of the base model);
   - the full update check (`Update_full.cfg` / `Update-full.cfg`; `Update.cfg` in v2/case-011);
   - its residual variant when the suite has one (`*_residual`, `*-rest`, `*_safety`, `*_core`, `*-noU4`,
     `Update-residual`): same constants, minus the checks the suite already saw violated, so that a known
     violation does not mask the rest;
   - the open update check (`Update_open.cfg` / `Update-open.cfg`).
   `Update_focused*` cfgs were dropped as near-duplicates of full/open (same checks, narrower Next) to keep
   within budget. The module of each cfg was resolved as the smallest local module defining all names the cfg uses
   (`scripts/inventory.py`). 73 cfgs in total (`selection.json`).
3. **+1 rule (`scripts/make_cfgs.py`).** Inside CONSTANT sections, every constant whose value is an integer literal
   and whose name matches `^Max|Limit$|Count$|Budget$` was raised by exactly one. In the selected cfgs this is every
   integer constant except `NoNode = 0` (a sentinel id). Model-value sets, sets of integers, strings, booleans and
   `<-` substitutions were untouched; no action, invariant, CONSTRAINT, VIEW or SYMMETRY was changed. Generated
   cfgs: `<arm>/<case>/<cfg>.plus1.cfg` (first line lists the changes); all changes are in `changes.json`.
   Constants raised from 0 to 1 (e.g. `MaxProposalLimit`, `MaxMembershipChanges`, `MaxCrashes`, `MaxLosses`)
   enable an action class the suite had switched off; this is a direct consequence of the mechanical rule.
4. **TLC (`scripts/run_jobs.py`).** `tla2tools.jar` (TLC 2026.11.06) + the case's CommunityModules jar, `-deadlock`.
   - simulation: `-simulate -depth 100 -seed 1 -workers 1`, `timeout 240 s`, `-Xmx4g`, 16 in parallel;
   - BFS: `-workers 8 -Xmx16g`, `timeout 300 s`, 2 in parallel (run after all simulations).
   Per cfg 540 s at most (cap 15 min); per suite ≤ 4 cfgs → ≤ 36 min of TLC wall time (cap 1 h).
   Simulation stats are from TLC's last per-minute progress line before the kill, so they lag by up to 60 s.
5. **Original re-runs.** For each +1 violation whose invariant had not already been seen violated on the same cfg
   in the suite's own logs/reports, the original (un-raised) cfg was re-run under the same simulation budget and
   seed (`variant=orig` rows in `runs.csv`).
6. **Baseline evidence** for "already appears without +1" comes from the suite's own logs under `spec/output/`
   (grep for the `-config` line / campaign header and the TLC `Error:` line) and its `bug-report.md` / `findings.json`.

## Constants changed per suite

Every selected cfg's changes are in the first line of its `<arm>/<case>/<cfg>.plus1.cfg` and in `changes.json`;
they are also the 4th column of the result table below. Left alone (and listed as the remaining bounds):

- `NoNode = 0` (v0/v1/v2 case-004): sentinel id, not a count.
- Model-value / set bounds that are the only bound on how many of something exist (not raised, by rule):
  `Server` (3 nodes everywhere; `MCServer`, `ReferenceServer` substitutions in 011/012), `Txn = {t1}` (case-002: one
  transaction), `Values = {v1}` and `ReadContexts = {ctx1}` (case-006), `Bodies`/`Others`/`Rest` and their `Valid*`
  subsets (case-003), `InitialVEHs`, `VEProposals`, `VEHValues`/`VEHeights`/`VEValues` (case-003 integer sets),
  `ElectNodes`, `TransferSources`, `TransferTargets`, `CrashNodes`, `InitialVoters` (case-004),
  `AllowedConfigs` (case-012), `InitialConfig`, `NodeOrder`, `TickPreVoteModes`, `PreVoteSetting`,
  `PreVoteFallbackPeers` (case-011).
- Bounds hard-coded in modules rather than cfgs were not touched (e.g. `CanonicalDepthBound == TLCGet("level") <= 23`
  and `TimeBudget == TLCGet("duration") <= 1740` in v2/case-002; the latter never binds within 300 s).
- `MaxDepth` (v1/case-002, used by the `DepthBound` CONSTRAINT) was raised 60→61 / 200→201 because it is a
  `Max*` count constant in the cfg; the CONSTRAINT itself was unchanged.

## Results per arm × case × cfg

Seconds in a VIOLATION cell are TLC wall time to the violation. "cex N states" is the length of the printed
counterexample (BFS: shortest). Trimmed logs: `<arm>/<case>/<cfg>.plus1.{sim,bfs}.log`; counterexamples:
`<arm>/<case>/<cfg>.plus1.{sim,bfs}.cex.txt` (full text when ≤ 40 kB, otherwise the action header of every state
plus the full last two states).

| arm | case | cfg | constants raised | +1 simulate (240 s, depth 100, seed 1) | +1 BFS (300 s, 8 workers) |
|---|---|---|---|---|---|
| v0 | case-002 | MC.cfg | MaxEpoch 2→3, MaxCrash 1→2, MaxDrop 1→2, MaxSnapshot 1→2 | no violation in budget (1306871 states, 1390 traces) | no violation in budget (depth 22, 3472858 distinct, queue 1103958) |
| v0 | case-002 | Update-full.cfg | MaxEpoch 2→3, MaxCrash 1→2, MaxDrop 1→2, MaxSnapshot 1→2 | VIOLATION NoSyncException (cex 65 states, 30s) | no violation in budget (depth 21, 3268102 distinct, queue 1041537) |
| v0 | case-002 | Update-open.cfg | MaxEpoch 2→3, MaxCrash 1→2, MaxDrop 1→2, MaxSnapshot 1→2 | no violation in budget (1134523 states, 1197 traces) | no violation in budget (depth 21, 3422325 distinct, queue 1345536) |
| v0 | case-003 | MC.cfg | MaxHeight 2→3, MaxBlocks 2→3, MaxCrashes 2→3, MaxAppRollbacks 1→2 | no violation in budget (13603712 states, 136038 traces) | exhausted (663754 distinct, depth 49, 6s) |
| v0 | case-003 | Update_full.cfg | MaxHeight 2→3, MaxBlocks 2→3, MaxCrashes 2→3, MaxAppRollbacks 1→2 | VIOLATION ContractLegalUpdateAccepted (cex 17 states, 2s) | VIOLATION ContractLegalUpdateAccepted (cex 6 states, 1s) |
| v0 | case-003 | Update_full_safety.cfg | MaxHeight 2→3, MaxBlocks 2→3, MaxCrashes 2→3, MaxAppRollbacks 1→2 | no violation in budget (13128434 states, 131285 traces) | exhausted (663754 distinct, depth 49, 6s) |
| v0 | case-003 | Update_open.cfg | MaxHeight 2→3, MaxBlocks 2→3, MaxCrashes 2→3, MaxAppRollbacks 1→2 | VIOLATION ContractLegalUpdateAccepted (cex 14 states, 3s) | VIOLATION ContractLegalUpdateAccepted (cex 6 states, 1s) |
| v0 | case-004 | MC.cfg | MaxTerm 3→4, MaxIndex 2→3, ElectionLimit 1→2, TransferLimit 2→3, AppendLimit 1→2, ReplicateLimit 2→3, MembershipLimit 1→2, AckLimit 2→3, CrashLimit 1→2, StaleLimit 1→2 | no violation in budget (1110748 states, 10932 traces) | no violation in budget (depth 19, 5311913 distinct, queue 3589640) |
| v0 | case-004 | Update_full.cfg | MaxTerm 3→4, MaxIndex 2→3, ElectionLimit 1→2, TransferLimit 2→3, AppendLimit 1→2, ReplicateLimit 2→3, MembershipLimit 1→2, AckLimit 2→3, CrashLimit 1→2, StaleLimit 1→2 | VIOLATION ElectOnlyByVoter (cex 24 states, 3s) | VIOLATION ElectOnlyByVoter (cex 11 states, 2s) |
| v0 | case-004 | Update_full_residual.cfg | MaxTerm 3→4, MaxIndex 2→3, ElectionLimit 1→2, TransferLimit 2→3, AppendLimit 1→2, ReplicateLimit 2→3, MembershipLimit 1→2, AckLimit 2→3, CrashLimit 1→2, StaleLimit 1→2 | no violation in budget (1034265 states, 10179 traces) | no violation in budget (depth 19, 4692474 distinct, queue 3197727) |
| v0 | case-004 | Update_open.cfg | MaxTerm 3→4, MaxIndex 2→3, ElectionLimit 1→2, TransferLimit 2→3, AppendLimit 1→2, ReplicateLimit 2→3, MembershipLimit 1→2, AckLimit 2→3, CrashLimit 1→2, StaleLimit 1→2 | VIOLATION ElectOnlyByVoter (cex 32 states, 4s) | VIOLATION ElectOnlyByVoter (cex 11 states, 3s) |
| v0 | case-006 | MC.cfg | MaxTerm 2→3, MaxLogLen 3→4, MaxCampaignLimit 2→3, MaxProposalLimit 1→2, MaxHeartbeatLimit 1→2, MaxReadLimit 2→3, MaxReadyLimit 6→7, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 8→9 | no violation in budget (798177 states, 4150 traces) | no violation in budget (depth 16, 3653867 distinct, queue 1986859) |
| v0 | case-006 | Update_full.cfg | MaxTerm 2→3, MaxLogLen 2→3, MaxCampaignLimit 2→3, MaxProposalLimit 0→1, MaxHeartbeatLimit 1→2, MaxReadLimit 2→3, MaxReadyLimit 8→9, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 8→9 | VIOLATION UpdReadAckAfterEnqueue (cex 53 states, 10s) | no violation in budget (depth 16, 3593386 distinct, queue 1930904) |
| v0 | case-006 | Update_open.cfg | MaxTerm 2→3, MaxLogLen 2→3, MaxCampaignLimit 2→3, MaxProposalLimit 0→1, MaxHeartbeatLimit 1→2, MaxReadLimit 2→3, MaxReadyLimit 8→9, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 8→9 | no violation in budget (1195855 states, 770 traces) | no violation in budget (depth 12, 3656737 distinct, queue 2500064) |
| v0 | case-010 | MC.cfg | MaxEpoch 2→3, MaxTxn 2→3, MaxRounds 1→2, MaxCrashes 1→2, MaxExits 1→2, MaxSnapshots 1→2 | no violation in budget (882131 states, 16739 traces) | no violation in budget (depth 24, 3318778 distinct, queue 1052248) |
| v0 | case-010 | Update-full.cfg | MaxEpoch 2→3, MaxTxn 2→3, MaxRounds 1→2, MaxCrashes 1→2, MaxExits 1→2, MaxSnapshots 1→2 | no violation in budget (840026 states, 15918 traces) | no violation in budget (depth 24, 3237452 distinct, queue 1030214) |
| v0 | case-010 | Update-open.cfg | MaxEpoch 2→3, MaxTxn 2→3, MaxRounds 1→2, MaxCrashes 1→2, MaxExits 1→2, MaxSnapshots 1→2 | no violation in budget (1827047 states, 54 traces) | no violation in budget (depth 10, 74812 distinct, queue 41962) |
| v0 | case-011 | MC.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | no violation in budget (1373564 states, 2855 traces) | no violation in budget (depth 14, 4629065 distinct, queue 2823988) |
| v0 | case-011 | Update-full-rest.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | VIOLATION PreVoteElectOnlyByVoter (cex 31 states, 64s) | no violation in budget (depth 13, 4056085 distinct, queue 2484843) |
| v0 | case-011 | Update-full.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | VIOLATION PreVoteNeverDemotesEstablishedLeader (cex 24 states, 10s) | no violation in budget (depth 14, 3907018 distinct, queue 2396145) |
| v0 | case-011 | Update-open.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | VIOLATION PreVoteNeverDemotesEstablishedLeader (cex 25 states, 6s) | no violation in budget (depth 14, 4178692 distinct, queue 2566578) |
| v0 | case-012 | MC.cfg | MaxTerm 1→2, MaxIndex 1→2, MaxElectionActions 1→2, MaxClientAppends 1→2, MaxMembershipChanges 0→1, MaxCrashes 0→1, MaxLosses 0→1 | no violation in budget (1756800 states, 4533 traces) | no violation in budget (depth 15, 9273983 distinct, queue 6028422) |
| v0 | case-012 | Update_full.cfg | MaxTerm 2→3, MaxIndex 2→3, MaxElectionActions 2→3, MaxClientAppends 1→2, MaxMembershipChanges 1→2, MaxCrashes 1→2, MaxLosses 1→2 | VIOLATION ProgressSortedAboveCommitted (cex 23 states, 5s) | VIOLATION ProgressSortedAboveCommitted (cex 8 states, 4s) |
| v0 | case-012 | Update_full_residual.cfg | MaxTerm 2→3, MaxIndex 2→3, MaxElectionActions 2→3, MaxClientAppends 1→2, MaxMembershipChanges 1→2, MaxCrashes 1→2, MaxLosses 1→2 | no violation in budget (1524988 states, 4259 traces) | no violation in budget (depth 14, 9262074 distinct, queue 6767035) |
| v0 | case-012 | Update_open.cfg | MaxTerm 2→3, MaxIndex 2→3, MaxElectionActions 2→3, MaxClientAppends 1→2, MaxMembershipChanges 1→2, MaxCrashes 1→2, MaxLosses 1→2 | VIOLATION MembershipOrder (cex 52 states, 1s) | VIOLATION ProgressSortedAboveCommitted (cex 8 states, 4s) |
| v1 | case-002 | MC.cfg | MaxEpoch 2→3, MaxCrash 1→2, MaxDrop 1→2, MaxSnapshot 1→2, MaxDepth 60→61 | no violation in budget (2099394 states, 31140 traces) | no violation in budget (depth 30, 6097322 distinct, queue 1699020) |
| v1 | case-002 | Update-full.cfg | MaxEpoch 3→4, MaxCrash 1→2, MaxDrop 1→2, MaxSnapshot 1→2, MaxDepth 200→201 | no violation in budget (3067276 states, 30669 traces) | no violation in budget (depth 31, 7220088 distinct, queue 2020109) |
| v1 | case-002 | Update-open.cfg | MaxEpoch 3→4, MaxCrash 1→2, MaxDrop 1→2, MaxSnapshot 1→2, MaxDepth 200→201 | no violation in budget (3044049 states, 30263 traces) | VIOLATION CommittedPersistedOnQuorum (cex 20 states, 15s) |
| v1 | case-003 | MC.cfg | MaxHeight 2→3, MaxBlocks 2→3, MaxCrashes 2→3, MaxAppRollbacks 1→2 | no violation in budget (11423650 states, 114237 traces) | exhausted (301069 distinct, depth 49, 4s) |
| v1 | case-003 | Update_full.cfg | MaxHeight 2→3, MaxBlocks 2→3, MaxCrashes 2→3, MaxAppRollbacks 1→2 | VIOLATION UnchangedVENotRejected (cex 22 states, 2s) | VIOLATION UnchangedVENotRejected (cex 6 states, 1s) |
| v1 | case-003 | Update_full_safety.cfg | MaxHeight 2→3, MaxBlocks 2→3, MaxCrashes 2→3, MaxAppRollbacks 1→2 | no violation in budget (12790265 states, 127903 traces) | exhausted (301069 distinct, depth 49, 4s) |
| v1 | case-003 | Update_open.cfg | MaxHeight 2→3, MaxBlocks 2→3, MaxCrashes 2→3, MaxAppRollbacks 0→1 | VIOLATION UnchangedVENotRejected (cex 14 states, 3s) | VIOLATION UnchangedVENotRejected (cex 6 states, 1s) |
| v1 | case-004 | MC.cfg | MaxTerm 2→3, MaxIndex 3→4, ElectionLimit 1→2, TransferLimit 1→2, AppendLimit 1→2, MembershipLimit 1→2, CrashLimit 1→2, StaleLimit 1→2 | no violation in budget (750221 states, 7058 traces) | no violation in budget (depth 19, 6050681 distinct, queue 4022456) |
| v1 | case-004 | Update_full.cfg | MaxTerm 2→3, MaxIndex 3→4, ElectionLimit 1→2, TransferLimit 1→2, AppendLimit 1→2, MembershipLimit 1→2, CrashLimit 1→2, StaleLimit 1→2 | VIOLATION CandidateIsVoterOfSnapshot (cex 26 states, 3s) | VIOLATION CandidateIsVoterOfSnapshot (cex 11 states, 2s) |
| v1 | case-004 | Update_open.cfg | MaxTerm 2→3, MaxIndex 3→4, ElectionLimit 1→2, TransferLimit 1→2, AppendLimit 1→2, MembershipLimit 1→2, CrashLimit 1→2, StaleLimit 1→2 | VIOLATION CandidateIsVoterOfSnapshot (cex 25 states, 2s) | VIOLATION CandidateIsVoterOfSnapshot (cex 11 states, 2s) |
| v1 | case-006 | MC.cfg | MaxTerm 2→3, MaxLogLen 3→4, MaxCampaignLimit 2→3, MaxProposalLimit 1→2, MaxHeartbeatLimit 1→2, MaxReadLimit 1→2, MaxReadyLimit 3→4, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 6→7 | no violation in budget (974396 states, 7011 traces) | no violation in budget (depth 16, 3770127 distinct, queue 1796714) |
| v1 | case-006 | Update_full.cfg | MaxTerm 2→3, MaxLogLen 2→3, MaxCampaignLimit 2→3, MaxProposalLimit 0→1, MaxHeartbeatLimit 1→2, MaxReadLimit 2→3, MaxReadyLimit 8→9, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 8→9 | VIOLATION ReadDeliveryJustifiedFresh (cex 55 states, 94s) | no violation in budget (depth 16, 3840840 distinct, queue 2014544) |
| v1 | case-006 | Update_open.cfg | MaxTerm 2→3, MaxLogLen 2→3, MaxCampaignLimit 2→3, MaxProposalLimit 0→1, MaxHeartbeatLimit 0→1, MaxReadLimit 2→3, MaxReadyLimit 8→9, MaxQuorumCheckLimit 0→1, MaxCrashLimit 2→3, MaxLoseLimit 0→1, MaxMsgBufferLimit 8→9 | VIOLATION ReadDeliveryJustifiedFresh (cex 55 states, 51s) | no violation in budget (depth 11, 1641899 distinct, queue 1014594) |
| v1 | case-010 | MC.cfg | MaxEpoch 2→3, MaxTxn 1→2, MaxRounds 2→3, MaxCrashes 1→2, MaxExits 1→2, MaxSnapshots 1→2 | no violation in budget (837381 states, 3323 traces) | exhausted (2291242 distinct, depth 61, 221s) |
| v1 | case-010 | Update-full-residual.cfg | MaxEpoch 2→3, MaxTxn 2→3, MaxRounds 2→3, MaxCrashes 1→2, MaxExits 2→3, MaxSnapshots 1→2 | no violation in budget (1125076 states, 13959 traces) | no violation in budget (depth 32, 5028253 distinct, queue 2399228) |
| v1 | case-010 | Update-full.cfg | MaxEpoch 2→3, MaxTxn 2→3, MaxRounds 2→3, MaxCrashes 1→2, MaxExits 2→3, MaxSnapshots 1→2 | VIOLATION ExitedLearnerMemoryBackedByLog (cex 68 states, 6s) | no violation in budget (depth 33, 4900886 distinct, queue 2333998) |
| v1 | case-010 | Update-open.cfg | MaxEpoch 2→3, MaxTxn 2→3, MaxRounds 2→3, MaxCrashes 1→2, MaxExits 2→3, MaxSnapshots 1→2 | VIOLATION RecoverableCommittedPrefix (cex 65 states, 4s) | VIOLATION OrderedHistoriesV1 (cex 15 states, 88s) |
| v1 | case-011 | MC.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxPreVoteCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | no violation in budget (1100937 states, 2044 traces) | no violation in budget (depth 13, 3966732 distinct, queue 2758817) |
| v1 | case-011 | Update-full-noU4.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxPreVoteCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | no violation in budget (1123042 states, 2086 traces) | no violation in budget (depth 12, 3819605 distinct, queue 2657498) |
| v1 | case-011 | Update-full.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxPreVoteCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | VIOLATION NoStalePreCandidateAtLeader (cex 26 states, 4s) | VIOLATION NoStalePreCandidateAtLeader (cex 10 states, 27s) |
| v1 | case-011 | Update-open.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxPreVoteCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | VIOLATION NoStalePreCandidateAtLeader (cex 34 states, 2s) | no violation in budget (depth 10, 6515345 distinct, queue 5522696) |
| v1 | case-012 | MC.cfg | MaxTerm 1→2, MaxIndex 1→2, MaxElectionActions 1→2, MaxClientAppends 2→3, MaxMembershipChanges 0→1, MaxCrashes 0→1, MaxLosses 0→1 | no violation in budget (1027396 states, 8828 traces) | no violation in budget (depth 13, 3341915 distinct, queue 2276657) |
| v1 | case-012 | Update_full.cfg | MaxTerm 1→2, MaxIndex 1→2, MaxElectionActions 1→2, MaxClientAppends 1→2, MaxMembershipChanges 1→2, MaxCrashes 0→1, MaxLosses 1→2 | VIOLATION ProgressSortedAboveCommitted (cex 19 states, 5s) | VIOLATION OneOutstandingMembership (cex 9 states, 4s) |
| v1 | case-012 | Update_open.cfg | MaxTerm 1→2, MaxIndex 1→2, MaxElectionActions 1→2, MaxClientAppends 1→2, MaxMembershipChanges 1→2, MaxCrashes 0→1, MaxLosses 0→1 | VIOLATION ProgressSortedAboveCommitted (cex 15 states, 12s) | VIOLATION ProgressSortedAboveCommitted (cex 9 states, 5s) |
| v2 | case-002 | MC.cfg | MaxEpoch 2→3, MaxCrash 1→2, MaxDrop 1→2, MaxSnapshot 1→2 | no violation in budget (1772439 states, 54406 traces) | no violation in budget (depth 21, 5268875 distinct, queue 1939066) |
| v2 | case-002 | Update-full.cfg | MaxEpoch 2→3, MaxCrash 1→2, MaxDrop 1→2, MaxSnapshot 1→2 | VIOLATION NewLeaderAckDurable (cex 72 states, 172s) | no violation in budget (depth 21, 5264327 distinct, queue 1941962) |
| v2 | case-002 | Update-open.cfg | MaxEpoch 3→4, MaxCrash 2→3, MaxDrop 1→2, MaxSnapshot 1→2 | no violation in budget (1637227 states, 17216 traces) | no violation in budget (depth 21, 5381520 distinct, queue 2111178) |
| v2 | case-003 | MC.cfg | MaxHeight 3→4, MaxBlocks 3→4, MaxCrashes 2→3, MaxAppRollbacks 1→2 | no violation in budget (13097077 states, 125379 traces) | exhausted (17281406 distinct, depth 62, 66s) |
| v2 | case-003 | Update_full.cfg | MaxHeight 3→4, MaxBlocks 3→4, MaxCrashes 2→3, MaxAppRollbacks 1→2 | VIOLATION UnchangedVEUpdateNotRejected (cex 20 states, 1s) | VIOLATION UnchangedVEUpdateNotRejected (cex 13 states, 1s) |
| v2 | case-003 | Update_full_core.cfg | MaxHeight 3→4, MaxBlocks 3→4, MaxCrashes 2→3, MaxAppRollbacks 1→2 | no violation in budget (9414470 states, 90125 traces) | exhausted (17281406 distinct, depth 62, 88s) |
| v2 | case-003 | Update_open.cfg | MaxHeight 3→4, MaxBlocks 3→4, MaxCrashes 2→3, MaxAppRollbacks 1→2 | VIOLATION UnchangedVEUpdateNotRejected (cex 31 states, 1s) | VIOLATION UnchangedVEUpdateNotRejected (cex 13 states, 1s) |
| v2 | case-004 | MC.cfg | MaxTerm 2→3, MaxIndex 2→3, ElectionLimit 1→2, TransferLimit 1→2, AppendLimit 1→2, MembershipLimit 1→2, CrashLimit 1→2, StaleLimit 1→2 | no violation in budget (1446014 states, 13353 traces) | no violation in budget (depth 22, 6513501 distinct, queue 3665911) |
| v2 | case-004 | Update_full.cfg | MaxTerm 2→3, MaxIndex 2→3, ElectionLimit 1→2, TransferLimit 1→2, AppendLimit 1→2, MembershipLimit 1→2, CrashLimit 1→2, StaleLimit 1→2 | VIOLATION ElectionByVoterOnly (cex 42 states, 1s) | VIOLATION ElectionByVoterOnly (cex 12 states, 2s) |
| v2 | case-004 | Update_open.cfg | MaxTerm 2→3, MaxIndex 2→3, ElectionLimit 1→2, TransferLimit 1→2, AppendLimit 1→2, MembershipLimit 1→2, CrashLimit 1→2, StaleLimit 1→2 | VIOLATION ElectionByVoterOnly (cex 51 states, 1s) | VIOLATION ElectionByVoterOnly (cex 12 states, 3s) |
| v2 | case-006 | MC.cfg | MaxTerm 2→3, MaxLogLen 3→4, MaxCampaignLimit 2→3, MaxProposalLimit 1→2, MaxHeartbeatLimit 1→2, MaxReadLimit 1→2, MaxReadyLimit 3→4, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 6→7 | no violation in budget (1001722 states, 7209 traces) | no violation in budget (depth 16, 3678806 distinct, queue 1798501) |
| v2 | case-006 | Update_full.cfg | MaxTerm 2→3, MaxLogLen 3→4, MaxCampaignLimit 2→3, MaxProposalLimit 1→2, MaxHeartbeatLimit 1→2, MaxReadLimit 2→3, MaxReadyLimit 12→13, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 8→9 | VIOLATION UpdReadAckFresh (cex 72 states, 22s) | no violation in budget (depth 16, 3762289 distinct, queue 1986792) |
| v2 | case-006 | Update_full_rest.cfg | MaxTerm 2→3, MaxLogLen 3→4, MaxCampaignLimit 2→3, MaxProposalLimit 1→2, MaxHeartbeatLimit 1→2, MaxReadLimit 2→3, MaxReadyLimit 12→13, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 8→9 | no violation in budget (725268 states, 3296 traces) | no violation in budget (depth 16, 3804370 distinct, queue 2017152) |
| v2 | case-006 | Update_open.cfg | MaxTerm 2→3, MaxLogLen 3→4, MaxCampaignLimit 2→3, MaxProposalLimit 0→1, MaxHeartbeatLimit 1→2, MaxReadLimit 2→3, MaxReadyLimit 12→13, MaxQuorumCheckLimit 1→2, MaxCrashLimit 1→2, MaxLoseLimit 1→2, MaxMsgBufferLimit 8→9 | VIOLATION UpdReadAckFresh (cex 58 states, 5s) | no violation in budget (depth 16, 2921117 distinct, queue 1580676) |
| v2 | case-010 | MC.cfg | MaxEpoch 2→3, MaxTxn 1→2, MaxLearnerExits 1→2 | no violation in budget (943859 states, 2792 traces) | no violation in budget (depth 45, 2615400 distinct, queue 459913) |
| v2 | case-010 | Update-full.cfg | MaxEpoch 2→3, MaxTxn 1→2, MaxLearnerExits 2→3 | VIOLATION OrderedHistories (cex 58 states, 2s) | VIOLATION OrderedHistories (cex 30 states, 34s) |
| v2 | case-010 | Update-open.cfg | MaxEpoch 1→2, MaxTxn 1→2, MaxLearnerExits 2→3 | no violation in budget (2363428 states, 6330 traces) | no violation in budget (depth 22, 3180766 distinct, queue 863728) |
| v2 | case-011 | MC.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxPreVoteCount 1→2, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | no violation in budget (1195923 states, 2022 traces) | no violation in budget (depth 12, 4066421 distinct, queue 2854842) |
| v2 | case-011 | Update-open.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 1→2, MaxPreVoteCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | VIOLATION StalePreVoteResponseIgnored (cex 11 states, 3s) | VIOLATION StalePreVoteResponseIgnored (cex 5 states, 2s) |
| v2 | case-011 | Update-residual.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxPreVoteCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | no violation in budget (1076322 states, 1764 traces) | no violation in budget (depth 12, 3486740 distinct, queue 2564636) |
| v2 | case-011 | Update.cfg | MaxTerm 2→3, MaxLogIndex 4→5, MaxElectionCount 2→3, MaxPreVoteCount 2→3, MaxMembershipCount 2→3, MaxCrashCount 1→2, MaxDropCount 1→2, MaxMessageCount 5→6 | VIOLATION StalePreVoteResponseIgnored (cex 26 states, 4s) | VIOLATION StalePreVoteResponseIgnored (cex 5 states, 2s) |
| v2 | case-012 | MC.cfg | MaxTerm 1→2, MaxIndex 0→1, MaxElectionActions 1→2, MaxClientAppends 1→2, MaxMembershipChanges 0→1, MaxCrashes 0→1, MaxLosses 0→1 | no violation in budget (1721339 states, 13638 traces) | no violation in budget (depth 16, 6282936 distinct, queue 3535777) |
| v2 | case-012 | Update_full.cfg | MaxTerm 2→3, MaxIndex 1→2, MaxElectionActions 2→3, MaxClientAppends 1→2, MaxMembershipChanges 1→2, MaxCrashes 1→2, MaxLosses 1→2 | no violation in budget (1267391 states, 11511 traces) | no violation in budget (depth 14, 5924404 distinct, queue 4384144) |
| v2 | case-012 | Update_open.cfg | MaxTerm 2→3, MaxIndex 1→2, MaxElectionActions 2→3, MaxClientAppends 1→2, MaxMembershipChanges 1→2, MaxCrashes 1→2, MaxLosses 1→2 | no violation in budget (1281931 states, 11737 traces) | no violation in budget (depth 14, 6055040 distinct, queue 4429727) |

### Counts per arm

| arm | cfgs | cfgs with any violation at +1 | sim violations | BFS violations | BFS exhausted | sum of run seconds |
|---|---|---|---|---|---|---|
| v0 | 25 | 11 | 11 | 6 | 2 | 8659 |
| v1 | 24 | 13 | 12 | 9 | 3 | 7056 |
| v2 | 24 | 10 | 10 | 7 | 2 | 8524 |

No run ended in a TLC error (parse/assumption/exception). BFS was exhausted at +1 for 7 cfgs
(v0/case-003 MC and Update_full_safety, v1/case-003 MC and Update_full_safety, v1/case-010 MC, v2/case-003 MC and
Update_full_core); every other non-violating BFS stopped at the 300 s budget with a non-empty queue.

## Violations at +1 and their judgment

Each distinct (arm, case, cfg, invariant) seen at +1. "Seen without +1" cites the suite's own runs on the same cfg
(paths relative to `results/<arm>/<case>/r1/output/spec/output/`) or our seed-1 re-run of the original cfg.
Finding ids refer to the suite's own `findings.json`. **All judgments are inference.**

| arm/case | cfg | invariant (first hit) | sim cex / BFS cex (states) | seen without +1? | judgment (inference) |
|---|---|---|---|---|---|
| v0/002 | Update-full | NoSyncException | 65 / – | yes: `mc/sim-update-full.log` | (i) known, suite MC-1 |
| v0/003 | Update_full, Update_open | ContractLegalUpdateAccepted | 17,14 / 6,6 | yes: `mc-v1-upd-full.log`, `mc-v1-upd-open.log` | (i) known, MC-1 |
| v0/004 | Update_full, Update_open | ElectOnlyByVoter | 24,32 / 11,11 | yes: `update-full-c1.log`, `update-open-c3-allprops.log` | (i) known, MC-1 |
| v0/006 | Update_full | UpdReadAckAfterEnqueue | 53 / – | yes: `update-full.log` | (i) known, MC-1 |
| v0/011 | Update-full, Update-open | PreVoteNeverDemotesEstablishedLeader | 24,25 / – | yes: `mc-upd-full.log`, `mc-upd-open.log` | (i) known, MC-1 |
| v0/011 | Update-full-rest | PreVoteElectOnlyByVoter | 31 / – | yes: `mc-upd-full-rest.log` | (i) known, MC-2 |
| v0/012 | Update_full, Update_open | ProgressSortedAboveCommitted | 23 / 8,8 | yes: `upd-full-final.log`, `upd-open-final.log` | (i) known, MC-1 |
| v0/012 | Update_open | MembershipOrder | 52 / – (BFS hit ProgressSortedAboveCommitted first) | **yes, our original re-run** (`Update_open.orig.sim`, 58 states); never reported by the suite (its Update_open runs stop at MC-1 first) | (i) model artifact, pre-existing: in the trace a follower's quorum-replicated entry is removed by the open-rely step `EnvFollowerConflict` (truncates down to the follower's own `committed`), the other node then wins term 2 and overwrites the old leader's committed entries; `MembershipOrder` is the first invariant to notice. The suite marks Update_open "provisional until Update_discharge passes". Not new at +1. |
| v1/002 | Update-open | CommittedPersistedOnQuorum | – / 20 | yes: `mc-F4a-update-open-bfs.log` | (i) known, MC-1 |
| v1/003 | Update_full, Update_open | UnchangedVENotRejected | 22,14 / 6,6 | yes: `update-full.log`, `update-open.log` | (i) known, MC-1 |
| v1/004 | Update_full, Update_open | CandidateIsVoterOfSnapshot | 26,25 / 11,11 | yes: `upd-full-all.log`, `upd-open-all.log` | (i) known, MC-1 |
| v1/006 | Update_full | ReadDeliveryJustifiedFresh | 55 / – | yes: `mc/sim_update_full.log` | (i) known, MC-1 |
| v1/006 | Update_open | ReadDeliveryJustifiedFresh | 55 / – | **no**: suite BFS on the original cfg was exhausted without error (`mc/update_open.log`) | **new at +1 for this cfg**, (i) known-and-reported: same invariant as suite MC-1; reachable here because +1 raised `MaxProposalLimit`, `MaxHeartbeatLimit`, `MaxQuorumCheckLimit`, `MaxLoseLimit` from 0 to 1, re-enabling actions the open cfg had switched off. |
| v1/010 | Update-full | ExitedLearnerMemoryBackedByLog | 68 / – | original cfg already violates in our re-run, but with RecoverableCommittedPrefix (84 states); suite's own Update-full runs: no violation in budget | (i) known-and-reported: both invariants are violated by the suite's own hunts (`final-update-hunt-trunc.log`, `final-update-hunt-leak-prefix.log`; MC-2 / MC-3). Not attributable to +1. |
| v1/010 | Update-open | RecoverableCommittedPrefix (sim), OrderedHistoriesV1 (BFS) | 65 / 15 | yes: `f2-upd-open.log` (OrderedHistoriesV1) and our original re-run (RecoverableCommittedPrefix, 55 states) | (i) known, MC-1/MC-3 |
| v1/011 | Update-full, Update-open | NoStalePreCandidateAtLeader | 26,34 / 10 (full) | yes: `v1-mc-update-full.log`, `v1-mc-update-open.log` | (i) known, MC-1 |
| v1/012 | Update_full, Update_open | ProgressSortedAboveCommitted; OneOutstandingMembership (full, BFS) | 19,15 / 9,9 | yes: `mc-upd-full-r1.log`, `mc-upd-full-r2.log`, `mc-upd-open-r2.log` | (i) known, MC-1 |
| v2/002 | Update-full | NewLeaderAckDurable | 72 / – | yes: `update/final-sim-update-full.log` | (i) known, MC-1 |
| v2/003 | Update_full, Update_open | UnchangedVEUpdateNotRejected | 20,31 / 13,13 | yes: `final/mc/Update_full.log`, `final/mc/Update_open.log` | (i) known, MC-1 |
| v2/004 | Update_full, Update_open | ElectionByVoterOnly | 42,51 / 12,12 | yes: `mc-Update_full.log`, `mc-Update_open.log` | (i) known, MC-1 |
| v2/006 | Update_full, Update_open | UpdReadAckFresh | 72,58 / – | yes: `mc-upd_full_sim.log`, `mc-upd_open.log` | (i) known, MC-1 |
| v2/010 | Update-full | OrderedHistories | 58 / 30 | **no**: suite BFS stopped at UpdIdleDbBackedByDisk (`mc/update-full.log`); our original re-run: no violation in 240 s | **new at +1 for this cfg**, (i) model artifact. Requires `MaxTxn` 1→2. BFS trace: leader s1 proposes txn 1, crashes before anything is durable, restarts, is re-elected in epoch 2 and proposes txn 2, so `prepared[s1] = <<2>>`, which is not a prefix of `TxnOrder = <<1, 2>>`. Losing a never-durable, uncommitted proposal is legal ZooKeeper behaviour; the invariant assumes globally contiguous txn ids. The suite's own OrderedHistories finding (MC-2, learner processor leak) is a different path reached only in its MaxTxn=2 hunt cfgs. Worth noting to the suite author as an over-strong invariant that would mask MC-2 in MaxTxn≥2 runs, not as a system bug. |
| v2/011 | Update | StalePreVoteResponseIgnored | 26 / 5 | yes: `mc-Update-full.log` (runs `Update.cfg`) | (i) known, MC-2 |
| v2/011 | Update-open | StalePreVoteResponseIgnored | 11 / 5 | suite never ran `Update-open.cfg` (only `Update-open-residual.cfg`); our original re-run violates it too (9 states) | (i) known, MC-2; not new at +1 |

Summary: 55 runs at +1 ended in a violation (33 simulations, 22 BFS), on 34 of the 73 cfgs.
Only **2** cfg/invariant pairs are violated at +1 but not seen on the same cfg without +1 (v1/006 Update_open
ReadDeliveryJustifiedFresh; v2/010 Update-full OrderedHistories). One more (v0/012 Update_open MembershipOrder)
had not been reported by the suite but is already present without +1. **No violation was judged (ii) possibly
worth reporting as a new system defect.** MC.cfg (the base model) never violated at +1 in any of the 21 suites,
and neither did any residual/rest/safety/core variant, except v0/011 `Update-full-rest` (PreVoteElectOnlyByVoter,
the suite's own MC-2 which that residual cfg still checks).

## Cost

- 73 cfgs × (240 s simulation + 300 s BFS) + 5 original re-runs (240 s).
  Sum of run seconds: 24,238 s (simulation 10,414 s; BFS 13,825 s). Elapsed wall clock for the whole experiment:
  about 2 h 12 min (06:13–08:25), simulations 16-way parallel, then BFS 2-way parallel × 8 workers.
- Time to violation: median 2.9 s over the 55 +1 runs that violated; maximum 172 s (v2/002 Update-full sim,
  NewLeaderAckDurable). Every violation except that one appeared within 95 s.
- Per suite (sum of run seconds, which overlapped):

| arm | case | sum of run seconds (sim + BFS + orig re-runs; runs overlapped) |
|---|---|---|
| v0 | case-002 | 1412 |
| v0 | case-003 | 498 |
| v0 | case-004 | 1094 |
| v0 | case-006 | 1392 |
| v0 | case-010 | 1622 |
| v0 | case-011 | 1523 |
| v0 | case-012 | 1117 |
| v1 | case-002 | 1336 |
| v1 | case-003 | 495 |
| v1 | case-004 | 550 |
| v1 | case-006 | 1288 |
| v1 | case-010 | 1406 |
| v1 | case-011 | 1414 |
| v1 | case-012 | 567 |
| v2 | case-002 | 1554 |
| v2 | case-003 | 639 |
| v2 | case-004 | 548 |
| v2 | case-006 | 1710 |
| v2 | case-010 | 1357 |
| v2 | case-011 | 1094 |
| v2 | case-012 | 1622 |


- Per-cfg state counts are in `runs.csv` (`states`, `distinct`, `queue`, `bfs_depth`, `sim_traces`).

## Measured facts vs inference

Measured (reproducible from `runs.csv`, the trimmed logs and the cfgs):
- which constants were raised in which cfg; TLC mode, budget, seed, seconds, states/depth reached and result of
  every run; the first violated invariant and counterexample length;
- whether the same invariant appears in the suite's own logs for the same cfg (by grep of those logs), and the
  results of the 5 original-cfg re-runs.

Inference (not verified against code or by reproduction):
- every (i)/(ii) judgment above, including mapping invariants to the suite's finding ids;
- the mechanism descriptions for v0/012 MembershipOrder (open-rely truncation) and v2/010 OrderedHistories
  (txn-numbering artifact), read off the counterexample state diffs;
- the claim that a violation is "new at +1": a 240 s seed-1 simulation (or the suite's bounded BFS) not finding it
  without +1 is not proof that it is unreachable at the original bounds, except where the suite's original BFS was
  exhausted (v1/006 Update_open).

## Limitations

- Only one seed and a 240 s simulation / 300 s BFS per cfg; most BFS runs stopped at depth 10–33 with large queues.
  TLC stops at the first violation, so a known violation in a non-residual cfg can mask others (residual cfgs were
  included to offset this).
- Hunt, focused, discharge and canary cfgs were not run; hard-coded module bounds were not raised.
- For v0/012 MembershipOrder the action names in the trace are generic (`OpenUpdateNext`), so the mechanism was
  reconstructed from per-state variable diffs.

## Files

- `selection.json`, `changes.json`: selected cfgs and every constant change.
- `runs.csv`: one row per TLC run (146 +1 runs + 5 original re-runs); `results.jsonl`: same data, raw.
- `scripts/`: `inventory.py` (cfg inventory/module resolution), `make_cfgs.py` (+1 rule), `make_jobs.py`,
  `run_jobs.py` (runner, log/cex trimming), `reparse.py`, `summarize.py` (runs.csv), `tables.py` (README tables),
  `jobs-*.jsonl` (the exact job lists).
- `<arm>/<case>/`: `*.plus1.cfg`, trimmed `*.log`, `*.cex.txt`.
- Full untrimmed logs remain in the work area `/mydata/bingzhuo/evidence-work/i5/logs/`.

## Known-gap reachability on the +1 cfgs (added by the main session after the run)

The agent did not see this check. The main session ran the decision predicates of `../evidence/` on the +1 constants.

| Gap | +1 cfg | Result |
|---|---|---|
| case-011 v0, a third election round | `MC.cfg` +1 | not reached: simulation 20 min (140M states), BFS 30 min (depth 16, 36.5M distinct) |
| case-006 v1, a reused read context | `MC.cfg` +1 | not reached: simulation 20 min (44M states), BFS 30 min (depth 19, 31M distinct) |
| case-004 v2, node removal | `MC.cfg` +1 | not run; the evidence probe with only `MembershipLimit = 2` reaches it in 23 states (inference: +1 allows a superset) |

With only the relevant bound raised and the others lowered, `../evidence/case-011/` reaches the case-011 gap at depth 17. Raising every bound at once grows the state space enough that neither gap is reached in budget.
