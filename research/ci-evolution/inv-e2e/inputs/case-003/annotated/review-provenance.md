# Provenance

All work used only `/work`, with no network access and no direct `git`. History was read only through `tools/hist.sh`. From step 2 on, the calls went through a logging wrapper (`out/tmp/h.sh`), which `exec`s `/work/tools/hist.sh` unchanged and appends each command to `out/tmp/hist-commands.log`. Scratch files are in `out/tmp/`.

## `tools/hist.sh` commands (in order)

| # | command | purpose / result |
|---|---|---|
| 0 | `tools/hist.sh` (no arguments) | usage text |
| 1 | `tools/hist.sh show f74f056a5:spec/abci/abci++_app_requirements.md` | verified the quotes at lines 831, 846, 854 (PersistedHeightRelationships, NormalPhaseIsSynchronized) |
| 2 | `tools/hist.sh log --oneline -- spec/abci/abci++_app_requirements.md` | file history; 19700acc2 present |
| 3 | `tools/hist.sh log -1 --format='%H %ad %s' base` | identifies the base revision (dab72adc0) |
| 4 | `tools/hist.sh log --oneline -1 f74f056a5` | intended to show f74f056a5. hist.sh always prepends `base`, so this printed the base commit |
| 5 | `tools/hist.sh log --oneline --follow -- spec/abci/abci++_app_requirements.md` | same list as #2 |
| 6 | `tools/hist.sh log --oneline base` (run twice, piped to `grep -c .` and `grep -n <cited commits>`) | confirmed f74f056a5, 19700acc2, 0bc539924, f82b7e2a1, 70a744558 are ancestors of base |
| 7 | `tools/hist.sh show --stat 19700acc2` | commit message and stats (crash-recovery spec rewrite) |
| 8 | `tools/hist.sh show 19700acc2 -- spec/abci/abci++_app_requirements.md` | confirms the explicit inequalities were removed and replaced by prose (the note in PersistedHeightRelationships is accurate) |
| 9 | `tools/hist.sh show --stat 0bc539924` | full commit message, which contains the quoted sentence |
| 10 | `tools/hist.sh show 0bc539924 -- state/execution.go types/params.go` | the diff adds ValidateUpdate. The message says what the PR adds, not what must happen to invalid updates |
| 11 | `tools/hist.sh show 70a744558:state/state.go` | verified the quote at line 276 and the "TODO: err or carry on?" fallback |
| 12 | `tools/hist.sh log -1 --format='%H %ad %s' 70a744558` | printed base (same `base` prefix as #4) |
| 13 | `tools/hist.sh show -s --format='%H %ad%n%B' 70a744558 f82b7e2a1` | commit messages ("types: params.Update()", "state: re-order funcs. fix tests") |
| 14 | `tools/hist.sh show f82b7e2a1 --stat` | stats |
| 15 | `tools/hist.sh show f82b7e2a1` (filtered with grep) | the error return is on both sides of the diff, so f82b7e2a1 only moves it |
| 16 | `tools/hist.sh log -S'Error updating consensus params: %v' --oneline -- state/state.go state/execution.go` | 35521b553 introduced the error return |
| 17 | `tools/hist.sh log -S'TODO: err or carry on?' --oneline -- state/state.go state/execution.go` | 35521b553 removed the fallback TODO; 56cada6a0 added it |
| 18 | `tools/hist.sh show -s --format='%H %ad%n%B' 35521b553 56cada6a0` | messages ("save historical consensus params", "Validate ConsensusParams returned from abci app"); no stated reason |
| 19 | `tools/hist.sh show 35521b553 -- state/state.go` | the fallback is replaced by `return fmt.Errorf(...)` (corrects the RejectedUpdateDoesNotInstall note) |
| 20 | `tools/hist.sh log -S'stateCopy := cs.state.Copy()' --oneline -- internal/consensus/state.go consensus/state.go` | 8e452aa0d (SuccessfulApplyAdvancesExactlyOne, saved-base clause) |
| 21 | `tools/hist.sh log -S'lastHeightParamsChanged' --oneline -- internal/state/execution.go state/execution.go state/state.go` | f82b7e2a1, c915719f8 (RejectedUpdateDoesNotInstall, change-height clause) |
| 22 | `tools/hist.sh show -s --format='%H %ad %s%n%b' 8e452aa0d c915719f8` | messages "fixed algorithm", "*State->State; SetBlockAndValidators->NextState"; no stated rule |
| 23 | `tools/hist.sh show 8e452aa0d -- consensus/state.go` | the state copy is introduced with only narrating comments |
| 24 | `tools/hist.sh show c915719f8 -- state/state.go state/execution.go` | `lastHeightParamsChanged` local introduced; no stated rule |
| 25 | `tools/hist.sh log -S'updateToState(stateCopy)' --oneline -- internal/consensus/state.go consensus/state.go` | 3e3c0083c |
| 26 | `tools/hist.sh show -s --format='%H %ad%n%B' 3e3c0083c` | message "Make order be decided first; Remove TMSP Commit/Rollback" |
| 27 | `tools/hist.sh show 3e3c0083c -- consensus/state.go` | only narrating comments ("Save the state."); no stated rule |

## Files read

Task and tools:
- `/work/ANNOTATION-RULES.md` (whole file)
- `/work/tools/hist.sh` (whole file); `ls /work/tools/network-guard`

Model:
- `/work/spec-annotated/base.tla`, `MC.tla`, `Trace.tla` (whole files)
- `/work/spec-annotated/*.cfg`, all 13 (whole files)
- `/work/spec-original/base.tla`, `MC.tla`, `Trace.tla` (diffed against spec-annotated and spec-reviewed); `/work/spec-original/*.cfg` (compared with `cmp`)

Source (`/work/source/`):
- `internal/consensus/replay.go`: lines 230-500 (Handshake, ReplayBlocks, replayBlocks), 505-517 (replayBlock); grep for every quoted line
- `internal/consensus/replay_test.go`: lines 560-930 (TestHandshakeReplay*, testHandshakeReplay, buildAppStateFromChain, buildTMStateFromChain); grep for line numbers and test names
- `internal/consensus/replay_stubs.go`: grep `func newMockProxyApp` (watch target)
- `internal/consensus/state.go`: lines 1760-1860 (finalizeCommit); grep for quoted lines
- `internal/state/execution.go`: lines 195-310 (ApplyBlock), 596-670 (updateState); grep for quoted lines and function names
- `internal/state/validation.go`: lines 25-45; grep line 39
- `internal/state/validation_test.go`: lines 25-150 (TestValidateBlockHeader)
- `internal/state/state.go`: lines 40-100 (State struct), 325-360 (genesis state)
- `internal/state/store.go`: lines 60-110 (Store interface); grep `Save`
- `internal/state/rollback.go`: lines 25-50; grep line 38 and `func Rollback`
- `internal/state/state_test.go`: lines 1005-1080 (TestConsensusParamsChangesSaveLoad)
- `internal/state/execution_test.go`: lines 38-82 (TestApplyBlock); grep `LastBlockHeight`
- `internal/state/helpers_test.go`: lines 247-268 (testApp.FinalizeBlock); grep in makeState
- `internal/state/*_test.go`: grep `ConsensusParamUpdates`
- `internal/store/store.go`: grep line 484 and `saveBlockToBatch`
- `types/params.go`: grep lines 145, 208, 257-258
- `types/params_test.go`: lines 54-76 (makeParams), 150-240 (TestConsensusParamsUpdate_VoteExtensionsEnableHeight)
- `node/node.go`: lines 335-375
- `node/setup.go`: lines 180-210 (doHandshake)
- `spec/abci/abci++_app_requirements.md`: lines 560-575, 595-630, 755-830, 895-960; heading grep
- `spec/abci/abci++_methods.md`: lines 630-690; grep for the consensus_param_updates text and headings
- `spec/abci/abci++_comet_expected_behavior.md`: lines 130-160; grep
- `spec/core/data_structures.md`: lines 56-116, 455-495; heading grep
- grep over all `*_test.go` for `ErrAppBlockHeightTooHigh` / the replay.go panic strings (none found)

Tools run: `java ... tla2sany.SANY` on `base.tla`, `MC.tla` and `Trace.tla` in `out/spec-reviewed/`, and `python3 -I` on the two check scripts in `out/tmp/` (`check_blocks.py`, `check_quotes.py`).
