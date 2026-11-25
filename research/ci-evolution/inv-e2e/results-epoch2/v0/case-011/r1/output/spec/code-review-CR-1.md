# CR-1 (code review): a rejected Pre-Vote never propagates the responder's higher term — permanent leaderless stall

Source: code review of the update (`artifact/` `3ab6cdd`); not a model-checking
finding. The model cannot express it at the current granularity: followers never
receive log entries and AppendEntries rejection/HigherVote step-down are not
modeled (see `analysis-report.md`, "Update-focused analysis", item 5).

## Mechanism

- `Engine::handle_pre_vote_resp` never updates the local vote: a rejection only
  sets the greater-log hint (`openraft/src/engine/engine_impl.rs:543-553`,
  comment "A Pre-Vote response never updates the local vote").
- `Engine::handle_pre_vote_req` never updates the responder's vote either
  (`engine_impl.rs:406-447`).
- With Pre-Vote enabled, a node raises its term only after a would-grant quorum
  (`raft_core.rs:2010-2035`, `engine_impl.rs:526-541`).
- The direct election path (old behavior, and still used when Pre-Vote is
  disabled) adopts the higher vote from a rejected real vote response
  (`engine_impl.rs:494-508`).

## Stuck state (5 voters {1..5}, 1 and 3 permanently crashed, 3 of 5 alive)

- Node 2: freshest log `(1,1,2)`, vote `(1,1)` committed, lease expired.
- Nodes 4, 5: log `(1,1,1)`, vote `(2,3)` uncommitted (they granted node 3's
  real vote at term 2; node 3 crashed before replicating to them).

Reachable by ordinary operation: leader 1 replicates entry 2 only to node 2 and
crashes; node 2 is briefly partitioned while 3,4,5 pass Pre-Vote and 4,5 grant
node 3's real vote; node 3 crashes; the partition heals.

- Node 2 pre-votes `(2,2)`: nodes 4/5 reject because `(2,2) < (2,3)`; node 2 never
  learns term 2.
- Nodes 4/5 pre-vote `(3,4)`/`(3,5)`: node 2 rejects (shorter log); they reach only
  2 of 5 grants.
- Nothing else can change any vote: no leader, no real vote request. The cluster
  is leaderless forever although a majority is alive and connected.

## Evidence

| Check | Revision | Result |
|---|---|---|
| `specula_repro_pre_vote_term_stall` (all three live nodes run Pre-Vote rounds, 10 rounds) | update `3ab6cdd` | FAILS: terms stay `[1, 2, 2]` (`spec/output/repro-engine.log`) |
| `specula_repro_pre_vote_term_stall_node2_alone` (node 2 retries alone, the randomized-timeout schedule) | update `3ab6cdd` | FAILS (`spec/output/repro-engine.log`) |
| `specula_control_direct_election_progresses` (same state, direct elections, node 2 alone) | update `3ab6cdd` | passes: node 2 adopts term 2 and wins at term 3 (`spec/output/repro-engine.log`) |
| same control | baseline `1adc857` (`work-old/`) | passes (`spec/output/repro-old-control.log`) |
| `tests/tests/elect/t94_specula_pre_vote_term_stall.rs::specula_pre_vote_term_stall_live_majority_elects` (5 nodes through RaftRouter/RaftCore: leader 0 replicates one entry only to node 1 and fails; nodes 2,3,4 elect W while node 1 is partitioned; W fails before replicating; node 1 rejoins) | FAILS: live voters `[1, 3, 4]` have no leader after 5 s, terms stay `[1, 2, 2]` (`spec/output/repro-integration-term-stall.log`) |
| `t94::specula_control_direct_election_live_majority_elects` (identical scenario, Pre-Vote disabled) | passes: node 1 becomes Leader at term 3 (`spec/output/repro-integration-term-stall.log`) |

The simulation drives the real `Engine` methods in the order RaftCore uses
(SendPreVote -> peers' `handle_pre_vote_req` -> filtered `handle_pre_vote_resp`);
it does not use the network or timers.

## Status

Code-review finding (no model-checking counterexample: outside the model's log
abstraction), reproduced end-to-end on the updated revision through the real
runtime and network fixture, with a direct-election control that recovers.
"Permanent" rests on the code argument above (no remaining mechanism changes any
vote); the test observes 5 s (about 17 maximum election timeouts) without a term
change. Severity estimate: High (loss of availability with a live majority).
