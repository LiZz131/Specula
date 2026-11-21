# Provenance

All evidence comes from `/work`: the source tree `/work/source/`, the model `/work/spec-original/`, and the git history through `tools/hist.sh`. No network access was used. No knowledge of later CometBFT versions was used as evidence.

## Rule deviation (disclosed)

Early on I ran `git -C /work/source log -1` once, to see whether the source tree was a repository. It failed with "fatal: not a git repository" and returned no data. After that, every history access went through `tools/hist.sh`, via a logging wrapper (`out/tmp/h.sh`) that appends each call to `out/tmp/hist_cmds.log` and then `exec`s `/work/tools/hist.sh` with the same arguments.

## Every `tools/hist.sh` command run

The list below is the content of `out/tmp/hist_cmds.log` in execution order. The first three were run directly, before the wrapper existed; the rest were logged by the wrapper. Quoting is shown as the shell received it: `-S<text>` is a single argument.

```
     1	tools/hist.sh   (no args, usage) -- via cat of script
     2	tools/hist.sh log --oneline -5
     3	tools/hist.sh log --oneline   (piped to wc -l: 9801 commits)
     4	tools/hist.sh log -Smust not mutate state.ConsensusParams --oneline -- internal/state/execution.go state/execution.go
     5	tools/hist.sh log -Sonly applies to the next height --oneline -- internal/state/execution.go state/execution.go
     6	tools/hist.sh log -SValidateUpdate --oneline -- internal/state/execution.go state/execution.go
     7	tools/hist.sh log -Sthe state should never be ahead of the store --oneline -- internal/consensus/replay.go consensus/replay.go
     8	tools/hist.sh show 0bc539924 --stat
     9	tools/hist.sh show 0bc539924 -- state/execution.go
    10	tools/hist.sh log -Smust not mutate --oneline -- state/execution.go state/state.go internal/state/execution.go
    11	tools/hist.sh log -Smust not modify the original --oneline -- types/params.go
    12	tools/hist.sh log -SnextParams.ValidateBasic --oneline -- state/execution.go state/state.go internal/state/execution.go
    13	tools/hist.sh show 70a744558
    14	tools/hist.sh show 70a744558:state/state.go
    15	tools/hist.sh log -SError updating consensus params --oneline -- state/state.go state/execution.go
    16	tools/hist.sh show f82b7e2a1 --stat
    17	tools/hist.sh show f82b7e2a1 -- state/execution.go
    18	tools/hist.sh log -Sthe state should never be ahead of the store --oneline
    19	tools/hist.sh log -Sstore should be at most one ahead of the state --oneline
    20	tools/hist.sh log -Sthe app should never be ahead of the store --oneline
    21	tools/hist.sh log -Sshould not be resumed until we --oneline
    22	tools/hist.sh log -Sthis violates the --oneline -- internal/state/rollback.go state/rollback.go
    23	tools/hist.sh show bc6785967
    24	tools/hist.sh blame -L 899,950 spec/abci/abci++_app_requirements.md
    25	tools/hist.sh show 19700acc2f --stat
    26	tools/hist.sh show 19700acc2f
    27	tools/hist.sh show 19700acc2f^:spec/abci/abci++_app_requirements.md
    28	tools/hist.sh log -1 --format=%h %s 19700acc2f^
    29	tools/hist.sh show -s --format=%h %P %s 19700acc2f
    30	tools/hist.sh show -s --format=%p 19700acc2f
    31	tools/hist.sh show f74f056a5:spec/abci/abci++_app_requirements.md
    32	tools/hist.sh log -SReload the state --oneline -- node/node.go node/setup.go
    33	tools/hist.sh log -Sand saves the new state and responses --oneline
    34	tools/hist.sh log -Sensures the result matches the current state --oneline
    35	tools/hist.sh log -SLastBlockHeight:                  header.Height --oneline -- state/execution.go internal/state/execution.go
    36	tools/hist.sh log -Sensures the result matches --oneline
    37	tools/hist.sh show ed4ce5ff6 -- node/node.go
    38	tools/hist.sh log -SReplayBlocks replays all blocks since --oneline
    39	tools/hist.sh log -SSave the results before we commit --oneline
    40	tools/hist.sh log -Suseful in case we crash after app.Commit --oneline
    41	tools/hist.sh show -s ebf815ee5
    42	tools/hist.sh show ebf815ee5 -- consensus/replay.go
    43	tools/hist.sh show 70a744558:state/state.go
    44	tools/hist.sh show f74f056a5:spec/abci/abci++_app_requirements.md
    45	tools/hist.sh show f74f056a5:spec/abci/abci++_app_requirements.md
    46	tools/hist.sh show 70a744558:state/state.go
    47	tools/hist.sh show -s --format=%B 0bc539924
    48	tools/hist.sh show -s --format=%B 0bc539924
    49	tools/hist.sh show f74f056a5:spec/abci/abci++_app_requirements.md
    50	tools/hist.sh show f74f056a5:spec/abci/abci++_app_requirements.md
    51	tools/hist.sh show f74f056a5:spec/abci/abci++_app_requirements.md
    52	tools/hist.sh show 70a744558:state/state.go
    53	tools/hist.sh show -s --format=%B 0bc539924
    54	tools/hist.sh show -s --format=%B 0bc539924
    55	tools/hist.sh show f74f056a5:spec/abci/abci++_app_requirements.md
```

Notes on the log:

- Line 1: I read the script with `cat` rather than running it with no arguments.
- Line 28: `log -1 … 19700acc2f^` printed the base commit (`dab72adc0`) because `hist.sh log` always prepends `base`. The parent was then found with `show -s --format=%p` (line 30), giving `f74f056a5`.
- Lines 34 and 36: `-S'ensures the result matches…'` returned nothing, because that phrase spans two lines in `replay.go:280-281`. Line 38 searched for a single-line fragment instead.
- Lines 44–55 (from `show f74f056a5:…` onward, apart from the manual line-number lookups at 43): issued by `out/tmp/check_evidence.py`, run twice, to re-verify `history` quotes.

Commits whose content was used as evidence or as context for a `note:`:

| Commit | What it gave |
|---|---|
| f74f056a5 (parent of 19700acc2) | `spec/abci/abci++_app_requirements.md:831,846,854`: the explicit height inequalities and the "we're done" condition in the old Crash Recovery section |
| 19700acc2 "spec:abci2.0 - clarify crash recovery mechanism (#469)" | the commit that rewrote that section (from `blame`) |
| 0bc539924 "Vote extensions: add proto fields for enabling extensions (#9865)" | commit message: "This PR also adds validation of the consensus param updates." |
| 70a744558 "types: params.Update()" | `state/state.go:276` "NOTE: must not mutate s.ConsensusParams"; `:281-282` fallback to the old params on validation failure |
| f82b7e2a1 "state: re-order funcs. fix tests" | validation failure changed from fall-back-and-continue to returning an error (code only, no stated reason) |
| bc6785967 "make ReplayBlocks logic exhaustive" | origin of the replay.go height-order comments (no extra rationale in the message) |
| ed4ce5ff6 "ADR-016: Update ABCI Info method for versions (#2662)" | origin of the node.go "Reload the state…" comment |
| ebf815ee5 "cs/replay: check appHash for each block (#3579)" | context only; not cited |

## Files read

Files from `/work/spec-original/` (all read in full with `cat`): base.tla, MC.tla, Trace.tla, base.cfg, MC.cfg, Trace.cfg, MC_hunt_scenario1_params.cfg, MC_hunt_scenario2_durability.cfg, MC_hunt_scenario3_recovery.cfg, MC_reach_accepted.cfg, MC_reach_app_replay.cfg, MC_reach_crash.cfg, MC_reach_handshake_complete.cfg, MC_reach_mock_replay.cfg, MC_reach_real_replay.cfg, MC_reach_rejected.cfg.

Tools: `/work/tools/hist.sh` (read in full).

Files from `/work/source/` (line ranges read; "grep" means the file was only searched):

| File | Lines read |
|---|---|
| internal/state/execution.go | 1-60, 180-320, 360-430, 540-820 |
| internal/state/state.go | 1-110, 300-353 |
| internal/state/store.go | 1-120, 180-330, 540-720 |
| internal/state/rollback.go | 1-115 |
| internal/state/validation.go | 33-47 (grep context) |
| internal/state/errors.go | grep only |
| internal/state/execution_test.go | 41-84; grep for test names and LastBlockHeight |
| internal/state/state_test.go | 660-722, 1005-1076; grep |
| internal/state/store_test.go | grep (test names, ConsensusParamUpdates) |
| internal/state/helpers_test.go | 205-275 |
| internal/state/validation_test.go | 95-125; grep |
| internal/state/export_test.go | grep only |
| internal/consensus/replay.go | 1-60, 195-544 |
| internal/consensus/replay_stubs.go | 55-95 |
| internal/consensus/replay_test.go | 560-930; grep (asserts, modes, Panics) |
| internal/consensus/state.go | 639-680, 1740-1870 |
| internal/store/store.go | 30-100, 395-520; grep (CONTRACT/panic) |
| internal/store/store_test.go | grep (test names) |
| internal/rpctrace/rpctrace.go | head (checked whether it was trace instrumentation; it is not) |
| types/params.go | 140-290; grep (method list) |
| types/params_test.go | 100-216; grep (test names) |
| node/node.go | 325-375; grep |
| node/setup.go | 187-204 |
| spec/abci/abci++_app_requirements.md | 265-285, 560-640, 700-812, 880-960; grep |
| spec/abci/abci++_methods.md | 40-60, 600-665; grep |
| spec/abci/abci++_comet_expected_behavior.md | 30-175; grep (headings) |
| spec/core/state.md | 1-140 |
| spec/core/data_structures.md | 60-120; grep (height rules, headings) |
| proto/cometbft/state/v1/types.proto, v1beta1/types.proto, v1beta2/types.proto | grep (ConsensusParamsInfo, consensus_params comments) |
| proto/cometbft/abci/v1/types.proto | 430-438 (grep context) |

Other searches (`grep -rn` over trees, reading only the matching lines):

- `spec/`, `docs/` (*.md): "handshake" (filtered), "consensus_param"/"ConsensusParam"/"param_updates"/"consensus param", "ConsensusParamsChanged", crash/"ahead of", header-height rules.
- `--include=*.go` over `/work/source`: "rpctrace"; trace event names (BlockStored, HandshakeStart, UpdateStateAccepted, none found); "ConsensusParamUpdates" in tests; "LastHeightConsensusParamsChanged"; "LoadLastFinalizeBlockResponse/LoadFinalizeBlockResponse"; "ErrAppBlockHeightTooHigh/StateBlockHeight/assert.Panics" in tests; "validating new consensus params/updating consensus params/UpdateState(" in tests; "Reload the state/Handshake(/doHandshake" in node/.

Scratch files in `out/tmp/`: `h.sh` (logging wrapper), `hist_cmds.log`, `annotate.py` (inserts the blocks), `check_evidence.py` and `check_evidence.out` (verification), `sany_*.out`, `ev_table.txt`.
