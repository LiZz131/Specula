# case-003 evidence: same bug state in all arms; were the PUR rewrites real weakenings?

Decision probes run with TLC on the exported final specs (`results/<arm>/case-003/r1/output/spec`). Each arm gets
`Probe003.tla` (`EXTENDS Update`; state predicates only, no new or changed actions) and probe cfgs built from the
arm's own `MC.cfg` (constants, `SPECIFICATION` kept; only the checked properties replaced). The one cfg with
changed constants is `v1/P-bugother-2o` (named in its first line).

## Probes

- `ProbeNoBug` (all arms): a basic-valid update that re-sends the current, already reached vote-extension enable
  height (`0 < E <= h`, `Abci` present, same value) has been rejected (`phase = "rejected"`). The implementation
  then fails `ApplyBlock` (`types/params.go:243-248` row 6, `internal/state/execution.go:622-625`).
- `OldValidity` (all arms): the validity conjunct that each arm dropped from `ParameterUpdateReflected` (PUR),
  written with the arm's own new-tree `ValidateUpdate`: while `phase = "updated"` with an update present, the update
  passes `ValidateUpdate(persistedParam, update, h)`. Checked together with `ProbeReceiverStable`
  (`phase = "responseSaved" => activeParam = persistedParam`), which justifies using `persistedParam` as the receiver.
- `OldCodeValidity` (all arms): the same conjunct with the old-tree `ValidateUpdate` verdict
  (`old-tree types/params.go:208-230`), i.e. the meaning of the old model's static `ValidParams`.
- `ProbeNoBugOtherChanged` (v1): `ProbeNoBug` where the update also changes the non-ABCI part.

## Results

| Arm | Cfg | Result |
|---|---|---|
| v0 | `P-bug-MC` | bug state reached, 6 states |
| v1 | `P-bug-MC` | bug state reached, 6 states |
| v2 | `P-bug-MC` | bug state reached, 13 states (initial VE heights are {0, 2}; E = 2 is reached only at the second block) |
| v0 | `P-old-MC` | **holds; exhaustive** (75,944 distinct, depth 34) |
| v1 | `P-old-MC` | **holds; exhaustive** (40,119 distinct, depth 33) |
| v2 | `P-old-MC` | **holds; exhaustive** (1,460,638 distinct, depth 46) |
| v0 | `P-oldcode-MC` | violated, 6 states: row 7 (enable 0 -> 2 at h = 1) accepted by the new code, rejected by the old |
| v1 | `P-oldcode-MC` | violated, 6 states: row 5 (cancel future height 2 -> 0 at h = 1) |
| v2 | `P-oldcode-MC` | violated, 6 states: row 5 |
| v1 | `P-bugother-MC` | own `MC.cfg` (`ValidOthers = {"o0"}`): **unreachable, exhaustive** (40,119 distinct) |
| v1 | `P-bugother-2o` | `ValidOthers = {"o0","o1"}` (two legal identities, as in the old cfg): reached, 6 states |

Reading: dropping the `ValidateUpdate` conjunct from PUR (v0, v2 by rewriting PUR; v1 by redefining the helper
`ValidParams`, `v1/base.tla:45`) admits **no** reachable state of any arm's `MC.cfg` -- the conjunct restated the
acceptance guard. Keeping the old-tree meaning instead would have flagged legal new behaviour (rows 5/7) within 6
states. v1's single legal non-ABCI identity does not hide the bug, but it excludes the realistic shape of it (the
application changes another parameter and echoes the unchanged `Abci` sub-record).

Files: `<arm>/*.log` TLC outputs; `<arm>/*.steps.txt` counterexample steps (`cex_steps.py`).
`./run.sh <arm> <cfg> [timeout]` reruns a probe.
