# I-4: Can agent dismissals be settled by a canary on the agent's own model?

## Question

In the 21 inv-e2e modeling runs (arms v0/v1/v2 x cases 002, 003, 004, 006, 010, 011, 012, `r1`),
agents sometimes closed a risk by argument ("not reachable", "safe because", "equivalent to",
"covered by finding X", "not modeled", "no finding") instead of by a check. This step asks,
for every such dismissal, whether it can be settled cheaply by running a canary on the
run's own TLA+ model, and records what happens when it is.

## Blindness rules followed

- Read only the runs' own artifacts under `results/<arm>/<case>/r1/` (modeling-brief.md,
  analysis-report.md, spec/bug-report.md, spec comments, invariant-evidence.json, TLC logs)
  and the starting list `scenario-census/dismissals.csv`.
- Not read: anything under `notes/`, any other file under `analysis/epoch-1/` (README,
  root-causes, case-*.md, evidence/, coverage/, scenario-census/README.md or items/), any Gold
  or grading material. No attempt was made to learn which defects are "known".
- Judgments of reachable states use only the code locations cited by the run itself.

## Method

1. **Completing the list.** For each run, a keyword scan (dismiss, unreachable, safe, harmless,
   equivalent, covered by, excluded, outside, pre-existing, code review, liveness only, no
   effect, unaffected, abstract, ...) of analysis-report.md, spec/bug-report.md and
   modeling-brief.md, followed by reading the surrounding sections (do-not-model lists,
   code-review sections, "Not reproduced" tables, exclusions, abstraction notes), Update.tla /
   UpdateProps.tla scope comments, and `invariant-evidence.json` entries (decision, notes,
   change notes, unresolved). Statements kept: those that close a risk or behavior without a
   check (argument, subsumption, equivalence, "not reachable" without a cited TLC result,
   exclusions). Statements that merely describe a finding, or that leave a question explicitly
   open, were not kept. Evidence-json weakenings were kept only where they state harmlessness;
   none of the json entries did so beyond what the prose already said.
   Each starting-list row is kept (column `in_starting_list = yes`); new rows have `no`.
   The starting list's `source` line numbers were used as given.
2. **Classes.** (a) checkable on the model; (b) scope exclusion (mechanism not in the model);
   (c) already backed (the cited TLC run / canary / trace / observation log exists in the run's
   outputs; budget-limited runs are noted as such); (d) other / too vague / about the old
   revision only.
3. **Canaries.** For each (a) item, a probe module `Probe_<id>.tla` that `EXTENDS Update`
   (all canary cfgs used here belong to `Update.tla`, which extends `MC`), adds no actions and
   changes none, and defines `NotCanary` (state invariant) or `NotCanaryAct == [][~Canary]_vars`
   (action property). The probe cfg is one of the run's own cfgs with constants,
   SPECIFICATION/INIT/NEXT, CONSTRAINT, VIEW and SYMMETRY kept and the INVARIANT/PROPERTY
   sections replaced by the negated canary (`run_probe.py` derives it). The canary text is taken
   from the dismissal's wording; where a subsumption claim names a finding, the canary requires
   that finding's characteristic condition to be absent. Some (a) items need no run:
   `structurally_unreachable` (a guard or assignment in the model, cited, makes the canary
   impossible) or `not_expressible` (the model has no variable that distinguishes the situation).
4. **Runs.** All work on copies under `/mydata/bingzhuo/evidence-work/i4/<arm>/<case>/spec/`.
   Simulation first (two independent 300 s rounds, `sim` and `sim2`, for items the first missed): `tlc2.TLC -simulate -depth 100 -workers 1 -deadlock`, 300 s wall
   (`timeout`), `-Xmx4g`. For items not reached, BFS: `-workers 8 -Xmx16g -deadlock`,
   `timeout 1800`, at most two BFS at a time (`run_bfs_lane.sh`). TLA+ tools:
   `/mydata/bingzhuo/src/Specula/lib/tla2tools.jar` + the run's `CommunityModules-deps.jar`.
   `states/` and `*_TTrace_*` are deleted after each run; metadirs are temporary.
5. **Judgment** (marked as such): for each reachable canary, whether the reached state looks
   like (i) an artifact of the model's abstraction or (ii) a behavior worth reporting, judged
   from the trace and the code the dismissal itself cites.

## Files

- `dismissals.csv` -- one row per item: arm, case, id, quote, source, in_starting_list, class,
  canary, cfg, result, depth, seconds (sim + bfs wall time), sim_result, sim_seconds,
  bfs_result, bfs_seconds, judgment, note.
- `items.jsonl` -- the hand-built ledger (one JSON object per dismissal) that `build_csv.py`
  merges with the probe results into `dismissals.csv`; `add_items.py` appends/updates it.
- `probes/<arm>/<case>/Probe_<id>.tla|.cfg` -- probe modules and derived cfgs;
  `Probe_<id>.{sim,bfs}.log` -- trimmed TLC output (statistics, action sequence of the
  counterexample, its final state); `.json` -- machine-readable result.
- `run_probe.py` (one probe: derive cfg, run TLC, trim log), `run_bfs_lane.sh` (BFS queue lane), `add_items.py`, `build_csv.py` -- scripts. Re-running a probe: `python3 run_probe.py <arm> <case> <id> Update <cfg> sim|bfs`.

## Counts

| arm | (a) checkable | (b) scope | (c) backed | (d) other | total | of which new (not in starting list) |
|---|---|---|---|---|---|---|
| v0 | 10 | 30 | 6 | 7 | 53 | 24 |
| v1 | 10 | 36 | 4 | 8 | 58 | 17 |
| v2 | 9 | 41 | 6 | 6 | 62 | 18 |
| all | 29 | 107 | 16 | 21 | 173 | 59 |

Starting-list rows (114) by class: a=20, b=71, c=12, d=11. New rows (59) by class: a=9, b=36, c=4, d=10.

## Reachability table (class a)

| id | arm/case | result | depth | sim s | bfs s | total s | cfg |
|---|---|---|---|---|---|---|---|
| v0c002_N01 | v0/case-002 | not_reached_in_budget |  | 600.5 | 1801.1 | 2401.6 | Update-hunt-loss-crash-tight.cfg |
| v0c002_N02 | v0/case-002 | not_reached_in_budget |  | 600.5 | 1800.9 | 2401.4 | Update-full.cfg |
| v0c004_S02 | v0/case-004 | reachable | 25 | 1.1 |  | 1.1 | Update_full_residual.cfg |
| v0c006_N03 | v0/case-006 | not_reached_in_budget |  | 600.4 | 1800.9 | 2401.3 | Update_full_nk.cfg |
| v0c006_N04 | v0/case-006 | not_expressible |  |  |  |  |  |
| v0c006_S04 | v0/case-006 | structurally_unreachable |  |  |  |  | Update_full_nk.cfg |
| v0c010_S02 | v0/case-010 | not_reached_in_budget |  | 600.4 | 1801.0 | 2401.4 | Update-full.cfg |
| v0c010_S04 | v0/case-010 | not_reached_in_budget |  | 600.4 | 1800.9 | 2401.3 | Update-full.cfg |
| v0c011_S05 | v0/case-011 | not_expressible |  |  |  |  |  |
| v0c012_S05 | v0/case-012 | not_reached_in_budget |  | 600.5 | 1800.6 | 2401.1 | Update_full_residual.cfg |
| v1c002_S06 | v1/case-002 | structurally_unreachable |  |  |  |  | Update-full.cfg |
| v1c003_S03 | v1/case-003 | not_reachable_exhaustive_bfs |  | 300.1 | 1.7 | 301.8 | Update_full.cfg |
| v1c004_S05 | v1/case-004 | not_reached_in_budget |  | 600.4 | 1800.8 | 2401.2 | Update_hunt_U3_voter.cfg |
| v1c006_S02 | v1/case-006 | structurally_unreachable |  |  |  |  | Update_full.cfg |
| v1c010_N01 | v1/case-010 | reachable | 40 | 1.3 |  | 1.3 | Update-full.cfg |
| v1c010_N01r | v1/case-010 | reachable | 32 | 600.4 | 101.5 | 701.9 | Update-full.cfg |
| v1c010_S03 | v1/case-010 | structurally_unreachable |  |  |  |  | Update-full.cfg |
| v1c010_S05 | v1/case-010 | not_reached_in_budget |  | 600.4 | 1800.9 | 2401.3 | Update-full.cfg |
| v1c011_S01 | v1/case-011 | reachable | 12 | 7.5 |  | 7.5 | Update-full.cfg |
| v1c011_S05 | v1/case-011 | reachable | 15 | 600.4 | 419.1 | 1019.5 | Update-full-U4.cfg |
| v2c002_S05 | v2/case-002 | reachable | 26 | 600.5 | 1701.6 | 2302.1 | Update-focused-syncedlog.cfg |
| v2c003_S02 | v2/case-003 | not_reachable_exhaustive_bfs |  | 300.2 | 8.1 | 308.3 | Update_full.cfg |
| v2c004_N02 | v2/case-004 | not_reachable_exhaustive_bfs |  | 600.5 | 1013.1 | 1613.6 | Update_canary_CanaryLearnerLeader.cfg |
| v2c006_N01 | v2/case-006 | structurally_unreachable |  |  |  |  | Update_full.cfg |
| v2c011_S06 | v2/case-011 | reachable | 25 | 10.9 |  | 10.9 | Update.cfg |
| v2c011_S09 | v2/case-011 | not_reached_in_budget |  | 600.5 | 1801.1 | 2401.6 | MC_hunt_U4_prevote_stale_round.cfg |
| v2c011_S10 | v2/case-011 | not_reached_in_budget |  | 600.4 | 1800.8 | 2401.2 | Update.cfg |
| v2c012_N01 | v2/case-012 | not_reached_in_budget |  | 600.3 | 1801.1 | 2401.4 | MC_reach_u3_follower_promotion.cfg |
| v2c012_S05 | v2/case-012 | not_expressible |  |  |  |  |  |

Result counts over class (a): not_expressible=3, not_reachable_exhaustive_bfs=3, not_reached_in_budget=11, reachable=7, structurally_unreachable=5

Check time per run item (sim + BFS wall clock, 21 items with a run): median 2401.1 s, mean 1556.3 s, min 1.1 s, max 2401.6 s. Items settled without a run (structural / not expressible) cost reading time only and are not in these numbers.
For reachable items alone: median 10.9 s, mean 577.8 s.

## Reachable canaries and judgments

All judgments below are the author's reading of the counterexample and of the code the
dismissal itself cites; they are marked "(judgment)" in `dismissals.csv` and are not measured.

- **v0c004_S02** (v0 case-004, modeling-brief.md:81-83): "A failed transfer leaves follower
  leases disabled until the vote changes ... Liveness/availability only; the model's lease
  abstraction already admits every acceptance." Reached in simulation (depth 25 in the recorded run, depth 18 in a first run; ~1 s): a
  transfer message to another target disables a follower's lease while the old leader stays
  leader with the same vote and no candidate exists. (judgment) (ii) as an availability
  behavior matching utime.rs:150-161; the model cannot show any safety consequence because
  `ReceiveVoteRequest` never reads the lease -- the "liveness only" half of the claim is
  untestable on this model rather than confirmed.
- **v1c010_N01** (v1 case-010, bug-report.md:110, not in the starting list): "Independent
  observation (not pursued ...): the TRUNC-to-maxCommittedLog path ... temporarily reducing the
  number of durable copies of a committed txn". Canary "a globally committed txn durable on at
  most a minority" reached in simulation (depth 40, ~1 s), but through Crash/Restart of the
  leader followed by `FormNewLeaderQuorum` reusing epoch/NEWLEADER acks that `Crash` and
  `Restart` leave unchanged, not through TRUNC. (judgment) (i) model artifact for this witness.
  A crash-free refinement (`v1c010_N01r`) was added; see the table for its result.
- **v1c011_S01** (v1 case-011, modeling-brief.md:300-302): "CR-review-1 (dismissed): same-term
  pre-vote rounds share a leader id, so a delayed earlier-round grant is counted; judged
  equivalent to a delayed in-round grant." Reached in simulation (depth 12, ~8 s): node 2 starts
  a timer Pre-Vote round, sends to node 1, an operator `ExternalPreElect` restarts the round
  with the same probe (term 2, node 2), and node 1's grant to the first round is in flight to
  the new round, which has not sent node 1 a request (`preSentReq`). (judgment) (ii): the
  run's cited comment (raft_core.rs:2066) says such responses should be ignored; the
  equivalence argument covers the probe value but not what may change between rounds (e.g.
  the frozen membership), so the dismissal is not settled by the argument.
- **v2c011_S06** (v2 case-011, UpdateProps.tla:69): "admin rounds (ExternalCommand::Elect
  { pre_vote: true }) are excluded: they check only is_voter and carry a TODO about leaders".
  Reached in simulation (depth 25, ~11 s): an operator Pre-Vote round on node 3 reaches quorum
  after node 3 became Leader and calls `elect()` on the Leader. (judgment) (ii): this is the
  state the cited debug assertion `leader.committed_vote >= vote` (engine_impl.rs:977-982)
  forbids; the exclusion rests on a TODO, not on an argument that the state is harmless.

- **v1c010_N01r** (refinement of v1c010_N01, crash-free): reached by BFS at depth 32 (101 s).
  s3 logs and flushes t1, exits, rejoins, is TRUNCated (t1 removed), and only then the leader
  counts s3's earlier ACK and commits t1, now durable on the leader alone. (judgment) (ii): this
  is exactly the path the dismissal names; on the model the committed txn has one durable copy
  out of three, so a single leader crash would leave none. "Not pursued" left a reportable
  behavior unchecked.
- **v1c011_S05** (v1 case-011, Update.tla:210-211): "Rounds started by an administrator on a
  node that was already Leader are excluded (pre-existing TODO at raft_core.rs:1685)." Not hit
  in two 300 s simulations, reached by BFS at depth 15 (419 s): an operator Pre-Vote round on
  the Leader reaches quorum and changes the Leader's vote. (judgment) (ii), as for v2c011_S06.
- **v2c002_S05** (v2 case-002, campaign-summary.md:63-64): "With one transaction (`Txn = {t1}`)
  no ghost is possible in those single-txn runs." Not hit in two simulations, reached by BFS at
  depth 26 (1702 s) in `Update-focused-syncedlog.cfg` (Txn = {t1}): s2 is broadcasting with
  leaderOf = s1 and holds t1 durably while s1 has become a follower of s3 and lost t1 through
  TRUNC. (judgment) (i) for the state (the property compares against a leader that no longer
  leads), but the dismissal as written is false on this model: a ghost under the revised
  property is possible with one transaction.

## What the exercise shows

- Most dismissals (class b) are scope exclusions: the mechanism (observers, reconfiguration,
  time, metrics, transport, apply plumbing, ...) is simply not in the model, so a canary on the
  model cannot settle them. They can only be settled by extending the model or by testing code.
- Of the class-(a) items, several were decided without running TLC because the model itself
  makes them structural (a guard such as `m.term = term[i]` or `running[s]` on the only action
  that could produce the state). In two such cases (v1c010_S03, v1c002_S06) the guard *is* the
  modeling choice the dismissal argues for, so "structurally unreachable" says only that the
  model encodes the claim, not that the claim is true of the code.
- Some (a) items are not expressible: the model carries no ghost that distinguishes the
  situation (round identity in v0 case-011, heartbeat-round identity in v0 case-006, the
  pre-skip acknowledgement values in v2 case-012). The v1 case-011 model happens to keep
  `preSentReq`, which made the same dismissal (cross-round grants) expressible there, and it
  was reachable in seconds.
- Four reachable items were found by simulation in about 1-11 s each; three more needed BFS
  (101 s, 419 s, 1702 s) after two 300 s simulations missed them. Three BFS runs exhausted the
  state space without reaching the canary (v1c003_S03, v2c003_S02: row 2 is excluded by the
  ValidateBasic guard `veh >= 0` / `ve >= 0`; v2c004_N02: learner leadership not reachable in
  the canary cfg, so that dismissal is confirmed for those bounds). Eleven items were reached
  by neither simulation nor a 30-minute BFS.

## Limits

- The completion of the list is a keyword scan plus section reading by one reader; it is more
  complete than the starting list but certainly not exhaustive. Several new rows are
  restatements of do-not-model lists that the starting list had recorded for some runs only.
- Classification is a judgment; borderline cases (e.g. "covered by discharge" with a
  budget-limited discharge run) were put in (c) with the budget noted.
- A canary is one reading of the dismissal. A different, equally faithful canary could reach
  or miss a state the chosen one does not. Where the first witness clearly took another path
  than the dismissal names (v1c010_N01) a narrower refinement was added rather than replacing
  the result.
- "Not reached in budget" is not a proof of unreachability; "exhausted" BFS results hold only
  for the cfg's constants, constraint and VIEW/SYMMETRY.
- Wall time includes JVM start and parsing (~1 s); simulations that time out count the full
  300 s. Two simulation rounds (`sim`, `sim2`, independent random seeds) were run for every
  item that the first round did not reach; their times are summed.
- The probe cfgs are the run's own cfgs; where that cfg uses a hunting CONSTRAINT, results are
  relative to that restriction.

## Pre-registered criteria and outcome (added by the main session after the run)

The criteria below were written before the run in the iteration plan; the agent did not see them.

| Criterion | Outcome |
|---|---|
| Recall: the 011 B v1 "CR-review-1 (dismissed)" canary is reachable | reachable (`v1c011_S01`, 7.5 s, depth 12) |
| Recall: the 011 C v2 "through MC-1/MC-2" canary is reachable | not reached in budget (`v2c011_S10`) |
| Noise: at most 3 reachable items per run unrelated to known defects | at most 5 over 21 runs |
| Cost: mean decision time per checkable item at most 10 min | mean 26 min, set by the budget caps on unreached items; 5 of the 7 reachable items within 10 min |

Why `v2c011_S10` was missed: a reachability canary checks the half of the claim about which nodes can
reach the step, not the claim that the risk is subsumed by MC-1/MC-2. A subsumption claim has to be
checked by fixing the subsuming finding and re-checking, which this method does not do.
