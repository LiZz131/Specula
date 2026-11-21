# Review decisions, one row per REQ-EVIDENCE block

Columns: property | old status | new status | intent changed | evidence lines retyped or removed | one-line reason

| property | old status | new status | intent changed | evidence lines retyped or removed | reason |
|---|---|---|---|---|---|
| TypeOK | model-internal | model-internal | no | none | Type invariant; block accurate, no source evidence expected. |
| PersistedHeightRelationships | requirement | requirement | no | none | All quotes found; each of the three conjuncts has a "should never" / panic rule (replay.go:373/377/381, f74f056a5 spec text, rollback.go:38, Crash Recovery spec); note is evidence-only. |
| SuccessfulApplyAdvancesExactlyOne | requirement | mixed | yes | none retyped or removed (test arrow narrowed to the case asserted, height + 10) | Evidence supports "new state height = block height, one above the state it ran on"; that this state is the *saved* one (stateStoreHeight + 1) has only impl evidence and no history rule, so it is clause `saved-base: unknown`. |
| RejectedUpdateDoesNotInstall | requirement | mixed | yes | none retyped or removed (arrows narrowed on execution.go:615, params.go:257, 70a744558, 0bc539924) | The "must not mutate state.ConsensusParams" rules and state.go:1808 support "not advanced, parameters untouched" for the input State only. The parameter-change height and the saved copy the formula compares against have only impl evidence (clauses `change-height`, `saved-copy`: unknown). The note misattributed the error-return change to f82b7e2a1; it was 35521b553. |
| ParameterUpdateReflected | requirement | requirement | yes | none retyped or removed (arrows narrowed on methods.md §FinalizeBlock, TestApplyBlock, 0bc539924, params_test.go:164) | Intent said "the update is the state's consensus parameters"; the evidence (data_structures §Execution, "apply to the consensus params") says the parameters are the result of applying the update. TestApplyBlock asserts only Version.Consensus.App, and the 0bc539924 message says only that validation was added. |
| NormalPhaseIsSynchronized | requirement | requirement | no | node.go:355 retyped comment → impl (state.go:1808 arrow narrowed) | node.go:355 ("Reload the state. ...") narrates the stateStore.Load that follows it. The intent is still supported by the Crash Recovery spec, testHandshakeReplay, f74f056a5 and the ApplyBlock / Store.Save contracts. |
| RecoveryNormalOnlySupported | requirement | requirement | yes | node.go:348 retyped comment → impl | node.go:348 ("Create the handshaker, which calls ...") narrates the doHandshake call, and its arrow added "before consensus starts". Intent changed from "the handshake" to "a handshake" because the formula tests cumulative coverage markers. |
| MCTypeOK | model-internal | model-internal | no | none | Type and counter-bound invariant; block accurate. |
| NeverReachedAcceptedUpdate | model-internal | model-internal | no | none | Reachability canary (MC_reach_accepted.cfg); intent matches `~("acceptedUpdate" \in coverage)`. |
| NeverReachedRejectedUpdate | model-internal | model-internal | no | none | Reachability canary (MC_reach_rejected.cfg); intent matches the formula. |
| NeverReachedCrash | model-internal | model-internal | no | none | Reachability canary (MC_reach_crash.cfg); intent matches the formula. |
| NeverReachedAppOnlyReplay | model-internal | model-internal | no | none | Reachability canary (MC_reach_app_replay.cfg); intent matches the formula. |
| NeverReachedRealReplay | model-internal | model-internal | no | none | Reachability canary (MC_reach_real_replay.cfg); intent matches the formula. |
| NeverReachedMockReplay | model-internal | model-internal | no | none | Reachability canary (MC_reach_mock_replay.cfg); intent matches the formula. |
| NeverReachedHandshakeComplete | model-internal | model-internal | no | none | Reachability canary (MC_reach_handshake_complete.cfg); intent matches the formula. |
| TraceMatched | model-internal | model-internal | no | none | Trace-completeness property (`<>(l > Len(TraceLog))`); block accurate. |

## Standard applied to every block

- **Quote check.** I opened each `source/` and `spec/` location and checked each history quote with `hist.sh show`. All 58 quotes are present (automated pass in `out/check.md`). A comment counts as `comment` only if it states a rule, intent, contract or reason. A comment that describes the call right after it is `impl`, which applies to node.go:348 and node.go:355. API doc comments on exported functions and interfaces (execution.go:206, store.go:77, replay.go:280, params.go:257) stay `contract`.
- **Support check.** Each arrow states only what its quote or test assertion says. The intent may claim no more than the non-impl evidence of its own block, judged only from the sources that block cites.
- **Status check.** Where only impl evidence remained for a part of a formula, I searched the history (`out/provenance.md` #20-#27) before settling on `unknown`.
- **Note check.** All 16 note lines describe only the evidence search. None describes the model or mentions concerns.md, so nothing was moved. Notes were edited only to fix a wrong commit (RejectedUpdateDoesNotInstall), to record my history searches, and to state the two retypes.
