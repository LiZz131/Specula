# Modeling brief coverage audit

## Scenario coverage

| Brief scenario | Base actions | Targeted safety config | Reachability evidence | Concrete/old-test evidence |
|---|---|---|---|---|
| 1. Election/current-term commit | `Campaign`, vote handlers, `BecomeLeader`, `HandleAppendResponse`, Ready | `MC_hunt_s1_election.cfg`, `MC_hunt_s2_replication.cfg` | `Reach_s1_leader.cfg` depth 7; `Reach_s2_commit.cfg` depth 12 | trace election/no-op commit; focused election/replication tests |
| 2. Replication under delay/loss | proposal, append handlers, `LoseMessage`, crash/restart | `MC_hunt_s2_replication.cfg`, `MC.cfg` | commit witness depth 12 | eight append/response pairs; `TestNetworkDrop`, `TestNetworkDelay` |
| 3. CheckQuorum | heartbeat handlers, `BroadcastHeartbeat`, `CheckQuorum` | `MC_hunt_s3_quorum.cfg`, `MC.cfg` | `Reach_s3_quorum.cfg` depth 9 | 15-event quorum-loss trace and focused leader-stepdown tests |
| 4. Exact-old ReadIndex | client/process/forward/response, heartbeat response, `ReadyPublish` | `MC_hunt_s4_readindex.cfg`, `MC_hunt_s5_forwarded_read.cfg` | Ready read depth 18; forwarded response depth 17 | 28-event safe-read trace and `TestNodeReadIndex` |

## Property wiring

All neutral brief properties are enabled in `MC.cfg`,
`MC_complete_core.cfg`, and every final `MC_hunt_*.cfg`:

| Brief property | TLA+ invariant | Why it is nontrivial / falsifiable |
|---|---|---|
| Type correctness | `MCTypeOK` | every transition changes finite records, sequences, and message fields |
| Election safety | `MCElectionSafety` | independently campaigning nodes add leaders to term history |
| Log matching | `MCLogMatching` | delayed/rejected append delivery can create different local suffixes |
| Committed-prefix agreement | `MCCommittedPrefixAgreement` | commits occur independently after quorum responses |
| Leader completeness | `MCLeaderCompleteness` | later campaigns after loss/crash compare prior commit history |
| Commit bounds | `MCCommitWithinLog` | append, heartbeat, Ready, crash, and restart all move indexes/logs |
| Message well-formedness | `MCMessagesWellFormed` | every vote/append/heartbeat/read constructor is checked |
| Read quorum justification | `MCReadDeliveryJustified` | local and forwarded reads publish only after recorded acknowledgement evidence |
| Ready no invention | `MCReadyNoInvention` | `ReadyPublish` moves produced records into the public sequence |

Both trace configs enable all nine properties plus `TraceCanProgress`, a real
transition-enabledness oracle, and `TraceMatched`, eventual consumption of all
records. `ValidatePost` is not a stub: it compares term, vote, role, leader,
commit, applied, full log-term sequence, read queue, active pending count, and
produced read count. The two traces exhaust 29 and 16 distinct replay states.

## Brief §6.1 question coverage

| Question | Configs capable of exercising it | Evidence retained |
|---|---|---|
| MC1 election/loss/re-election safety | `MC.cfg`, `MC_hunt_s1_election.cfg`, `MC_hunt_s2_replication.cfg` | complete election search; broad and replication bounded logs; leader/commit witnesses |
| MC2 quorum reset/delayed heartbeat/read authority | `MC.cfg`, `MC_hunt_s3_quorum.cfg`, `MC_hunt_s4_readindex.cfg` | complete quorum search; quorum and Ready-read witnesses |
| MC3 duplicate context/FIFO/Ready justification | `MC_hunt_s4_readindex.cfg`, `MC_hunt_s5_forwarded_read.cfg`, `Trace.cfg` | local Ready and forwarded-response witnesses; exact-old pending map remains stale after queue advance in trace |

## Bounds and honest status

The main three-node configuration was stopped by its two-minute outer timeout;
its last periodic report had 1,633,425 generated and 426,837 distinct states at
depth 17 with no reported invariant violation. The final complete-core config
exhausted 109,936 generated / 26,255 distinct states through depth 23 with no
error. Election and quorum targeted configs also exhausted their spaces.
Replication and both ReadIndex target configs are timeout-limited. These are
`LIMITED_COVERAGE`, not proof.

## Incremental update c780d355 — coverage audit

Filled from the actual cfg files in `spec/` (not from intent).

### Update Scenario coverage

| Brief §8 Scenario | Reference actions (base.tla) | Update.tla focus | Targeted cfgs | Reachability witness | Fresh trace |
|---|---|---|---|---|---|
| U1 release frees pending state | `HandleHeartbeatResponse` | `AffectedActions`, `UpdPendingMatchesQueue` | `Update_full*.cfg`, `Update_focused*.cfg`, `Update_hunt_forwarded.cfg` | `Reach_update_freed.cfg` (HuntReadFreed) | `quorum_read`, `read_reuse` |
| U2 same-term reuse + delayed earlier ack | `ProcessReadIndex`, `HandleHeartbeat`, `HandleHeartbeatResponse`, `BroadcastHeartbeat` | `UpdReadAckFresh` | `Update_hunt_stale_ack.cfg`, `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg` | `Reach_update_reuse.cfg`, `Reach_update_reuse_served.cfg`, `Reach_update_stale_ack.cfg` | `read_reuse`, `stale_ack_reuse` |
| U3 stale read index after newer-term commit | U2 actions + election/replication actions | `UpdReadIndexLinearizable` | `Update_hunt_linearizable.cfg` (BFS + simulation), `Update_full.cfg` | MC counterexample / trace evidence (see bug-report) | `stale_ack_reuse` |
| U4 forwarded reads and role changes | `ForwardReadIndex`, `HandleReadIndexRequest`, `HandleReadIndexResponse`, role transitions (R1-R3) | `UpdReadStateOnlyAtLeader`, `ReadDeliveryJustified` | `Update_hunt_forwarded.cfg`, `Update_full_rest.cfg` | `Reach_update_forwarded_freed.cfg`, `Reach_update_leader_stepdown.cfg` | `forwarded_read`, `stepdown_pending` |

### Update property wiring

| Property | Enabled in |
|---|---|
| UpdPendingMatchesQueue | Update_full, Update_full_rest, Update_focused, Update_focused_rest, Update_open, Update_hunt_stale_ack, Update_hunt_forwarded, Trace.cfg (TrUpd…) |
| UpdReadStateOnlyAtLeader | Update_full, Update_full_rest, Update_focused, Update_focused_rest, Update_open, Update_hunt_forwarded, Trace.cfg |
| UpdReadAckFresh | Update_full, Update_focused, Update_open, Update_hunt_stale_ack, Update_hunt_forwarded, Trace.cfg, Trace_stale_ack_evidence_fresh.cfg |
| UpdReadIndexLinearizable | Update_full, Update_focused, Update_open, Update_hunt_stale_ack, Update_hunt_linearizable, Trace.cfg, Trace_stale_ack_evidence_lin.cfg |
| Control (ElectionSafety) | every Update_*.cfg |
| DischargeContext (action property) | Update_discharge.cfg |
| EnvWithinRely (action property) | Update_open.cfg |

All V0 brief properties remain enabled in `MC.cfg`, `MC_complete_core.cfg`, and
the inherited `MC_hunt_*.cfg`, which were rerun on the updated reference.
`*_rest.cfg` variants keep exploring after the read-freshness violations by
omitting only the two already-violated properties; they are not substitutes
for the full configs.
