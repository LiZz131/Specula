# Review summary

## Counts

| measure | count |
|---|---|
| blocks reviewed (in-scope properties, one block each) | 16 |
| kept unchanged (`review: ok`) | 11 |
| changed | 5 |
| intent changed | 4 (SuccessfulApplyAdvancesExactlyOne, RejectedUpdateDoesNotInstall, ParameterUpdateReflected, RecoveryNormalOnlySupported) |
| status changed | 2 (both requirement → mixed) |
| evidence lines retyped | 2 (node.go:348 and node.go:355, comment → impl) |
| evidence lines removed | 0 |
| evidence arrows narrowed | 10 (SuccessfulApply 1, RejectedUpdate 4, ParameterUpdateReflected 4, NormalPhase 1) |
| quotes not found at their location | 0 of 58 |
| note sentences moved to concerns.md | 0 (no note described the model; no concerns.md references) |
| note facts corrected | 1 (error-return change is 35521b553, not f82b7e2a1) |

## Status matrix (old → new)

| old \ new | requirement | mixed | unknown | impl-abstraction | model-internal | total |
|---|---|---|---|---|---|---|
| requirement | 4 | 2 | 0 | 0 | 0 | 6 |
| model-internal | 0 | 0 | 0 | 0 | 10 | 10 |
| total | 4 | 2 | 0 | 0 | 10 | 16 |

New clause lines: SuccessfulApplyAdvancesExactlyOne has `block-height` (requirement) and `saved-base` (unknown). RejectedUpdateDoesNotInstall has `not-installed` (requirement), `change-height` (unknown) and `saved-copy` (unknown).

## The five blocks I was least sure about

1. **RejectedUpdateDoesNotInstall.** I accepted that "NOTE: must not mutate state.ConsensusParams" / "must not modify the original" plus state.go:1808 directly imply "a rejected update leaves the State's parameters and height as they were". A stricter reading would say they only forbid in-place mutation while the candidate is computed, which would make `not-installed` unknown too and the whole block `unknown`. The `saved-copy` clause is also a judgement call, because the old intent said "before that block", not "saved".
2. **SuccessfulApplyAdvancesExactlyOne.** I made `saved-base` unknown by judging only this block's own citations. The ApplyBlock / Store.Save contracts cited under NormalPhaseIsSynchronized cover part of the link, though not that the next block is executed on the saved state. Reading `state(h+1) <- Execute(state(h), …, block(h))` as "new state height = block height" also depends on the spec's indexing convention.
3. **NormalPhaseIsSynchronized.** Retyping node.go:355 rests on judging that "It will have the Version.Consensus.App set by the Handshake…" explains the reload rather than stating a rule. After the retype, in-memory = saved after a handshake with no replay is covered only by impl. I kept `requirement` because the ApplyBlock / Store.Save contracts directly give in-memory = saved after every applied block.
4. **RecoveryNormalOnlySupported.** node.go:348 contains a purpose phrase ("to sync CometBFT with the app"), which could be read as a reason and so kept as `comment`. The status does not depend on it. The "the → a handshake" intent change follows the formula's cumulative coverage markers and changes nothing in practice in this model.
5. **ParameterUpdateReflected.** I kept `requirement`, but the validity conjunct rests on per-parameter "Must have" constraints, the VoteExtensionsEnableHeight rule and a commit message that only says validation was added. No text says what CometBFT must do with an invalid update. The intent rewording (resulting parameter set rather than "the update") is a precision fix that someone else might call unnecessary.
