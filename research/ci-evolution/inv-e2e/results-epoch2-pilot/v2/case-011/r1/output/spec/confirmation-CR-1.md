# Confirmation — CR-1: Pre-Vote backward-compatibility documentation contradicts the code

- **Source**: Code Review (update reconnaissance, defect ledger D-U4; no model counterexample)
- **Novelty**: NEW (no prior Specular record; blind run)
- **Status**: FALSE POSITIVE (as an implementation defect: code, code comments, and tests agree; only the protocol document is stale)
- **Severity**: Low (documentation)
- **Location**: `openraft/src/docs/protocol/pre_vote.md:56-63` vs `openraft/src/network/v2/network.rs:158-161`, `openraft/src/network/vote_trait.rs` (default `pre_vote`), `openraft/src/core/raft_core.rs:1460-1470`

## Description

`pre_vote.md` says the default `RaftNetworkV2::pre_vote` returns `Unreachable`
and that "A node treats an `Unreachable` Pre-Vote response as a grant". The code
does the opposite: the default implementation returns
`Ok(VoteResponse::new(rpc.vote, None, true))` (`network.rs:158-161`), and a
transport error, including `Unreachable`, is logged and not counted
(`raft_core.rs:1460-1470`, doc comment at `:1379-1383`).

## Investigation / reproduction

- Developer intent in code comments (`network.rs` doc of `pre_vote`,
  `raft_core.rs:1379-1383`) and the test
  `tests/tests/elect/t12_pre_vote.rs:241 pre_vote_unreachable_peer_is_not_a_grant`
  ("an Unreachable Pre-Vote response must not count toward the quorum") all
  agree with the code. The rolling-upgrade goal of the document is still met by
  the granting default implementation.
- No reproduction attempted: there is no behavioral consequence in the code;
  only an operator reading `pre_vote.md` would be misled about which network
  error makes a mixed-version cluster fall back to normal elections.

## Recommendation

Update `pre_vote.md` "Backward compatibility" to describe the granting default
implementation and that transport errors are not grants.
