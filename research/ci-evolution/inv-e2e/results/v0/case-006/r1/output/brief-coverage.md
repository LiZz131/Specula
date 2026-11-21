# Modeling brief coverage audit (V1)

Filled from the actual cfg files in `spec/` (V1). V0 audit text is preserved
in `/work/previous/.specula-output/brief-coverage.md`.

## Scenario coverage

| Brief scenario | Base actions | Targeted config(s) | Reachability evidence | Fresh trace evidence |
|---|---|---|---|---|
| 1. Election/current-term commit | Campaign, vote handlers, BecomeLeader, HandleAppendResponse, Ready | `MC_hunt_s1_election.cfg`, `MC.cfg`, `Update_full.cfg` | `Reach_s1_leader.cfg`, `Reach_s2_commit.cfg` | every trace (elections, no-op commit) |
| 2. Replication under delay/loss | ClientProposal, append handlers, LoseMessage, Crash/Restart | `MC_hunt_s2_replication.cfg`, `MC.cfg` | `Reach_s2_commit.cfg` | quorum_read and all read traces |
| 3. CheckQuorum | BroadcastHeartbeat, HandleHeartbeat(Response), CheckQuorum | `MC_hunt_s3_quorum.cfg`, `MC.cfg` | `Reach_s3_quorum.cfg` | quorum_loss, step_down_reads |
| 4. ReadIndex (local) | ClientReadIndex, HandleHeartbeatResponse, ReadyPublish | `MC_hunt_s4_readindex.cfg` | `Reach_s4_ready_read.cfg`, `Reach_s6_Published.cfg` | quorum_read, read_reuse |
| 5. Forwarded ReadIndex | ForwardReadIndex, HandleReadIndexRequest/Response | `MC_hunt_s5_forwarded_read.cfg` | `Reach_s5_forwarded_read.cfg`, `Reach_s6_RemoteRelease.cfg` | forwarded_read |
| 6a. Reuse lifecycle (update) | HandleHeartbeatResponse (delete), ProcessReadIndex | `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg` | `Reach_s6_Reenqueue.cfg` (depth 18), `Reach_s6_ReuseRelease.cfg` (19) | read_reuse, forwarded_read |
| 6b. Delayed acknowledgement across reuse (update) | + HandleHeartbeat, Campaign/BecomeLeader of a newer leader | `MC_hunt_s6_stale_ack.cfg`, `MC_hunt_s6_linearizable.cfg`, `MC_hunt_s6_linearizable_guided*.cfg` | `Reach_s6_StaleAckCounted.cfg` (22) | delayed_ack, stale_read_reuse |
| 6c. Forwarded reuse (update) | ForwardReadIndex, HandleReadIndexRequest/Response | `Update_full.cfg` | `Reach_s6_RemoteRelease.cfg` (17) | forwarded_read |
| 6d. Reset interaction (repair) | reset paths in Campaign/BecomeLeader/vote/append/heartbeat/CheckQuorum | `Update_full.cfg` (+ `UpdPendingQueueAgreement`) | — (trace-validated) | step_down_reads, higher_term_reads |
| FIFO prefix release | HandleHeartbeatResponse | `Update_full.cfg` | `Reach_s6_PrefixRelease.cfg` (17) | — |

## Property wiring (read from cfg files)

| Property | Defined | Enabled in |
|---|---|---|
| MCTypeOK … MCReadyNoInvention (V0 nine) | base/MC | `MC.cfg`, `Update_full*.cfg`, `Update_focused*.cfg`, `Update_open*.cfg`, inherited hunts (as in V0), all trace cfgs (base names) |
| UpdPendingQueueAgreement | UpdateProps | `Update_full*`, `Update_focused*`, `Update_open*`, `MC_hunt_s6_stale_ack`, trace cfgs |
| UpdQueueNoDuplicates | UpdateProps | `Update_full*`, `Update_focused*`, `Update_open*`, trace cfgs |
| UpdReadAckAfterEnqueue | UpdateProps | `Update_full`, `Update_focused`, `Update_open`, `MC_hunt_s6_stale_ack`, trace cfgs (+ delayed_ack witness cfg) |
| UpdReadIndexLinearizable | UpdateProps | `Update_full*`, `Update_focused*`, `Update_open*`, `MC_hunt_s6_*`, trace cfgs |
| UpdPublishedFromRelease | UpdateProps | `Update_full*`, `Update_focused*`, `Update_open*`, `MC_hunt_s6_linearizable*`, trace cfgs |
| DischargeContext | Update | `Update_discharge.cfg` |

`*_nk.cfg` variants drop only `UpdReadAckAfterEnqueue` after MC-1 was
recorded, so the remaining properties keep being explored.

## Brief §6.1 coverage

| Question | Config | Outcome |
|---|---|---|
| V0 MC1–MC3 | inherited hunts on the V1 model | `spec/bug-report.md` Not Reproduced table |
| MC-Q1 | `MC_hunt_s6_stale_ack.cfg`, `Update_full.cfg`, `Update_focused.cfg` | violated (21–22 states) -> MC-1 |
| MC-Q2 | `MC_hunt_s6_linearizable_guided_v2.cfg` | violated (37 states) -> MC-1 consequence; unguided BFS budget-limited at depth 28 |
| MC-Q3 | traces `step_down_reads`/`higher_term_reads` (V0 model rejects them) + `UpdPendingQueueAgreement` in full/focused/open | V0 model defect repaired; no violation after repair (bounded) |
