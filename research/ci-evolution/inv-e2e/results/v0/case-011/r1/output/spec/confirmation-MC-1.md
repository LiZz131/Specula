# Confirmation — MC-1: stale Pre-Vote round demotes a freshly established leader

- **Source**: MC (actual model-checking counterexamples)
- **Novelty**: NEW within this run's evidence (introduced by the `update` commit; no prior Specula finding; no external tracker consulted — blind run)
- **Status**: REPRODUCED
- **Severity**: Medium (availability / leader stability; no committed-entry safety violation observed). Debug builds: the new leader's RaftCore panics.
- **Source revision**: `artifact/` commit `update` 3ab6cddc34a5bf127747434bb41e20a1b9ef7769
- **Update attribution**: introduced by the update (new mechanism: Pre-Vote round + `handle_pre_vote_resp → elect()`); the exact-old code had no deferred election trigger that could survive leader establishment.

## 1. Investigation (code reachability)

| Step | Code | Reachable? |
|---|---|---|
| Candidate's election timer fires while its election is in flight; tick has no in-flight-candidate check for multi-voter configs and calls `pre_elect()` when Pre-Vote is enabled | `core/raft_core.rs:1959-2036` | yes (`Config::enable_pre_vote = Some(true)` or runtime toggle) |
| Alternatively an operator calls `trigger().elect(true)` on the candidate (voter check only) | `core/raft_core.rs:1683-1691` | yes (public API) |
| `pre_elect()` creates `pre_candidate` with probe `(term+1, self)` and keeps `candidate` | `engine/engine_impl.rs:298-322` | yes |
| A delayed granted vote response for the in-flight election completes the quorum; `establish_leader()` takes `candidate` only | `engine/engine_impl.rs:450-472, 855-881` | yes |
| `update_vote(committed)` → `update_internal_server_state` → `become_leader` (not `become_following`), so `pre_candidate` is not cleared | `engine/handler/vote_handler/mod.rs:106-162, 172-230, 234-250` | yes |
| A peer that granted the in-flight vote (vote `(term,self,uncommitted)`, no lease) grants the probe | `engine/engine_impl.rs:414-447` | yes |
| RaftCore delivers the late Pre-Vote response: `pre_candidate.is_some()` and equal leader id | `core/raft_core.rs:1803-1820, 2067-2090` | yes |
| Quorum → `self.elect()` on the established leader; `do_elect` bumps the term, vote becomes uncommitted, `server_state = Candidate`, the Leader object is retained | `engine/engine_impl.rs:530-541, 262-289` | yes |
| Next leader-handler access asserts `leader.vote >= state.vote` | `engine/engine_impl.rs:964-990` | debug builds panic |

Developer intent evidence (from the updated tree itself): the tick refuses to
start elections on a Leader (`raft_core.rs:1966-1969`); the Pre-Vote design note
says the requester stays as it is until a quorum would grant and that Pre-Vote
exists to avoid disrupting a healthy leader (`docs/protocol/pre_vote.md:14-48`);
`trigger().elect(true)` is documented as the non-disruptive manual election
(`raft/trigger.rs:47-58`); stale *vote* responses are filtered once the
candidate is gone (`raft_core.rs:2038-2064`). No comment accepts a stale
Pre-Vote round outliving leadership.

## 2. Model-checking evidence

| Run | Spec / cfg | Result |
|---|---|---|
| U1 hunt | `Update` / `MC_hunt_prevote_leader.cfg` | `PreVoteNeverDemotesEstablishedLeader` violated, 12 states — `spec/output/mc-hunt-prevote-leader.log` |
| U1 hunt, timer-only (no admin trigger) | `Update` / `MC_hunt_prevote_leader_tickonly.cfg` (`TickOnlySpec`) | violated, 14 states — `spec/output/mc-hunt-prevote-leader-tickonly.log` |
| Full update check (complete MCNext) | `Update` / `Update-full.cfg` | violated, depth 14 — `spec/output/mc-upd-full.log` |
| Concrete focused / open | `Update-focused.cfg`, `Update-open.cfg` | violated (consistent with full) |
| Consequence variant (U3) | `Update-full-rest.cfg` | `PreVoteElectOnlyByVoter` violated: the leader with the inherited round removes itself (joint → uniform `{3}`), then the stale grant makes the non-voter start an election — `spec/output/mc-upd-full-rest.log` |
| Model control with the candidate fix (establish_leader cancels the round) | `spec/fixcheck/` | see `spec/bug-report.md` (U1/U3 hold within the explored bounds) |

Timer-only counterexample (14 states, 3 voters, no crash/drop/membership):
tick(1) Pre-Vote (1,1) → node 3 grants → node 1 elects term 1 → persists →
tick(1) again while Candidate: Pre-Vote (2,1) → vote request to 3 → node 3
grants (1,1) and persists → node 1 becomes Leader (1,1,committed) with the
(2,1) round still alive → node 3 answers the (2,1) probe: granted (its vote is
(1,1) uncommitted, no lease) → node 1 receives the grant → quorum → `elect()` →
vote (2,1) uncommitted, role Candidate, Leader object retained.

## 3. Trace validation of the implementation path

The engine-level suffix of the counterexample is a validated fresh trace:
`traces/stale_pre_vote_after_establish.ndjson` (PreElect → RunCommands →
HandleVoteResponse [leader established, pre-candidate kept] → RunCommands →
HandlePreVoteResponse [term 2→3, role Candidate, leader object kept]);
TLC replay PASS (`spec/output/trace-stale_pre_vote_after_establish.log`); five
single-field mutants of this trace are rejected
(`spec/output/trace-mutation-check.log`).

## 4. Reproduction

Commands (from `.specula-output/`; each source tree builds in its own
`CARGO_TARGET_DIR` — an earlier shared target dir let cargo reuse an rlib built
from a fix-control copy, so those logs were superseded and rerun, see
`spec/changelog.md`):

```bash
harness/repro/run-repro.sh all                                             # update revision (work-source)
SPECULA_REPRO_SOURCE=$PWD/fixcheck-source  SPECULA_REPRO_LABEL=mc1-fix-only           harness/repro/run-repro.sh all
SPECULA_REPRO_SOURCE=$PWD/fixcheck2-source SPECULA_REPRO_LABEL=candidate-fix-combined harness/repro/run-repro.sh all
```

| Test | Level | Interface | Update revision | MC-1 candidate fix | Combined candidate fix |
|---|---|---|---|---|---|
| `harness/repro/specula_repro_stale_pre_vote_test.rs` | Engine | real `Engine` methods; response delivered only if RaftCore's filter would deliver it | FAILED: `(Candidate, T3-N1 uncommitted)` instead of `(Leader, T2-N1 committed)` — `spec/output/repro-MC-1-engine-update.log` | PASS — `repro-MC-1-engine-mc1-fix-only.log` | PASS — `repro-MC-1-engine-candidate-fix-combined.log` |
| `harness/repro/t90_specula_stale_pre_vote.rs` | Runtime (3 RaftCore nodes, router network) | `trigger().elect(false)`, then `trigger().elect(true)` while the election is in flight; post-hook delays node 2's responses (vote 300 ms, pre-vote 600 ms, below the 1000 ms RPC ttl) | FAILED 3/3: node 1's RaftCore panics `leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)` at `engine_impl.rs:977`; client write returns `Fatal(Panicked)` — `spec/output/repro-MC-1-runtime-update.log` | PASS 3/3: stays Leader at term 2, write commits — `repro-MC-1-runtime-mc1-fix-only.log` | PASS 3/3 — `repro-MC-1-runtime-candidate-fix-combined.log` |

The runtime test reaches the stale round through the public cautious-election
trigger because the default tick path needs the in-flight vote response to
arrive after the candidate's election timeout yet before the vote RPC ttl
(= `election_timeout_min`), a window that depends on storage/scheduling delay
and is not deterministic in the in-memory fixture. The timer-only path is
established by the model counterexample and by the engine-level test, which
uses the exact engine state that the tick produces.

Old-version control: not applicable — the exact-old revision has no Pre-Vote
round, `pre_elect`, `enable_pre_vote`, or `trigger().elect(bool)`; the tests do
not compile there. In the exact-old code the same operator sequence
(`elect()` twice) bumps the term immediately at the second trigger and cannot
demote a leader established later.

The candidate fixes (`harness/repro/candidate-fix-sanity.patch`: cancel the round in
`establish_leader`; `harness/repro/candidate-fix-combined-sanity.patch`: additionally
re-check `is_voter` before the Pre-Vote-triggered `elect()`) are sanity controls
showing the tests discriminate; they are not claimed upstream fixes.

## 5. Consequence

An automatic, fault-free interleaving (no crash, no message loss; only
delivery delay) makes a leader that has just won an election abandon its
leadership and start a new election at a higher term. In release builds the
node keeps a Leader object whose committed vote is below its own vote while it
campaigns; its followers hold its lease and reject the new vote request until
the lease expires, so the cluster has no functioning leader for at least a lease
period. In debug builds the node's RaftCore panics (the leader-vote assertion),
taking the node down. If the leader had meanwhile removed itself from the
membership, the stale round makes a non-voter start an election (U3 variant).

## 6. Recommendation

Cancel the Pre-Vote round when leadership is established (clear
`pre_candidate` in `establish_leader`/`become_leader`), and/or have the
`PreVoteResponse` handler ignore responses unless the node is still a
non-leader whose vote is the one the round probed from. Optionally skip
`pre_elect` while a real election is still in flight.
