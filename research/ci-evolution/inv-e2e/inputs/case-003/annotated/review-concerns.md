# Concerns

## 1. Sentences moved out of `note:` lines

**None.** I read every sentence of all 16 `note:` lines against the rule in `ANNOTATION-RULES.md` and the review task (no statements about how the model's actions or helpers behave, whether it matches the code, where it is weaker, stronger or a proxy, or what might be wrong, unmodelled, vacuous or a false alarm). Each sentence describes the evidence: what was searched, what was not found, what a quote or test covers, or how a commit changed the text. No block mentions `concerns.md`.

| property | note verdict |
|---|---|
| TypeOK, MCTypeOK, 7 × NeverReached*, TraceMatched | "no source evidence searched or expected …"; evidence-only |
| PersistedHeightRelationships | spec history (19700acc2), spec wording, replay.go:373 wording, test search; evidence-only |
| SuccessfulApplyAdvancesExactlyOne | what the protocol text relates; missing non-impl link; test search; evidence-only |
| RejectedUpdateDoesNotInstall | what the comments speak of; history of the fallback; test search; evidence-only (one factual commit error corrected, not moved) |
| ParameterUpdateReflected | what the validity clause rests on; missing text and test; spec wording; evidence-only |
| NormalPhaseIsSynchronized | which evidence supports which part; test runners; evidence-only |
| RecoveryNormalOnlySupported | test coverage of crash points; grammar line; missing text; evidence-only |

## 2. Reviewer observations about the model (not moved from any note)

I noticed these while checking that each intent describes what its formula checks. They are recorded here because they concern the model, not the evidence. The model is unchanged.

- **RecoveryNormalOnlySupported.** `coverage` only grows, so `"handshakeStarted" \in coverage` and `"handshakeComplete" \in coverage` mean "some handshake ever started/completed", not "the latest handshake". With `MaxCrashes = 2` (MC.cfg, scenario 2/3), the first conjunct can be met by an earlier handshake. In the current `Next`, phase `"normal"` is reached after `"handshake"` only through `CompleteHandshake`, so this does not weaken the check today. It would matter if another path to `"normal"` were added.
- **ParameterUpdateReflected.** The conjunct `pendingParam \in ValidParams` follows directly from `UpdateStateAccepted`'s guard (`pendingParam = NoParam \/ pendingParam \in ValidParams`) together with `updatePresent = (pendingParam /= NoParam)`. It cannot fail while that guard stays. In `Trace.tla`, `TraceValidParams` also includes every accepted proposed parameter.
- **SuccessfulApplyAdvancesExactlyOne.** Both conjuncts follow from the guards of `SaveBlock` / `SelectRealReplay` / `SelectMockReplay` (pending block = stored state + 1) and `ApplyBlockStart` (`stateHeight = stateStoreHeight`), plus `stateHeight' = pendingBlockHeight` in `UpdateStateAccepted`. The `saved-base` clause (status unknown) is therefore enforced by a model guard that reflects consensus/state.go:1822, not a stated rule.
