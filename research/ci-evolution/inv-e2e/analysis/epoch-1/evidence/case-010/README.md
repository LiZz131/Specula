# case-010 evidence: can each arm's model reach the SyncRequestProcessor leak on a serving learner exit?

Decision probes run with TLC on the exported final specs (`results/<arm>/case-010/r1/output/spec`). Each arm gets
`Probe010.tla` (`EXTENDS Update`; action properties and state predicates only, no new actions) and probe cfgs that
keep the arm's own constants, `INIT`/`NEXT`, `ACTION_CONSTRAINT`, `SYMMETRY` and replace the checked properties with
one probe. Shared variables: `role`, `running`, `syncComplete`, `syncQueued`, `durable`; the exit step and
"serving" use each arm's own definitions:

| | exit step | serving (`canShutdown`) |
|---|---|---|
| v0 | `LearnerShutdown`: `syncStage` becomes `EXITED` (`base.tla:311`) | `syncComplete[f]` (its `zkRunning`, `base.tla:318`) |
| v1 | `LearnerExit`: FOLLOWING -> LOOKING, `learnerStage' = "NONE"` | `ZkServing(f)` (`base.tla:174`) |
| v2 | `LearnerExit`: FOLLOWING -> LOOKING, `learnerStage' = "IDLE"` | `LearnerZkRunning(f)` (`base.tla:704`) |

- `ProbeNoServingExitLoss`: on a serving exit (process alive), some record that was in `syncQueued` before the step
  is not in `durable'` after it (old code drains and flushes in `LearnerZooKeeperServer.shutdown()`).
- `ProbeNoServingExitThreadAlive` (v1, v2): a serving exit adds to `leakedQueued` (the sync thread survives).
- `ProbeNoServingExitWithQueue` (frame canary): a serving exit happens with a non-empty `syncQueued`.
- `SyncEntryJustifiedOrig` / `SyncEntryJustifiedNoExitedExemption` (v0): the prior-suite property and v0's form minus
  its first relaxation, to see which states the relaxations let through.
- `SnapshotPublishedValid` (v1): the original property on v1's regular cfgs that check only `...V1`.

| Arm | Cfg | Built from | Result |
|---|---|---|---|
| v1 | `P-L-full` | own `Update-full.cfg` as is | violated, 23 states (20,815 distinct) |
| v1 | `P-L-huntleak` / `P-T-huntleak` | own `Update-hunt-leak.cfg` as is | violated, 4 states / 4 states |
| v1 | `P-L-prior` | own `Update-control-prior-leak.cfg` (PRIOR semantics) | complete, no violation (238,362 distinct) |
| v2 | `P-L-full` | own `Update-full.cfg` as is | violated, 25 states (38,892 distinct) |
| v2 | `P-L-leaknew` / `P-T-leaknew` | own `Update-leak-new.cfg` as is | violated, 24 / 25 states |
| v2 | `P-L-leakold` | own `Update-leak-old.cfg` (old code) | stopped by hand after ~7 min, depth 44, 5.9M distinct, no violation: no result |
| v0 | `P-Q-mc1det` | own `Update-hunt-mc1-deterministic.cfg` (its MC-1 cfg) | frame canary violated, 26 states: serving exit with `syncQueued = <<1>>`, which is flushed into `durable` |
| v0 | `P-L-mc1det` | same, loss probe | stopped by hand after ~10 min, depth 53, 2.2M distinct, no violation: no result |
| v0 | `P-SEJ-mc1det` | same, prior `SyncEntryJustified` | violated, 23 states (deposed leader LOOKING in BROADCAST) |
| v0 | `P-SEJ1-mc1det` | same, v0 form without the EXITED exemption | violated, 24 states (serving learner just after `LearnerShutdown`) |
| v1 | `P-SPV-MC-snapshot-complete` | own `MC-snapshot-complete.cfg`, original SPV | complete, no violation (744 distinct) |
| v1 | `P-SPV-MC-recovery-complete` | own `MC-recovery-complete.cfg`, original SPV | complete, no violation (25,240 distinct) |

v0 cannot represent the leak: `LearnerShutdown` (`base.tla:318-330`) appends the whole `syncQueued` to `durable`
and empties the queue when the server is running, and the model has no surviving sync thread. The loss probe is
false on every serving exit by construction; `P-Q-mc1det` shows the precondition is reachable.

Files: `<arm>/*.log` are the TLC outputs; `<arm>/*.steps.txt` list each counterexample step with the changed
variables (`cex_steps.py`). `./run.sh <arm> <cfg> [timeout]` reruns a probe.
