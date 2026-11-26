# Confirmation — CR-1: Pre-Vote documentation says `Unreachable` counts as a grant

- **Source**: Code Review (update reconnaissance; no model-checking counterexample — transport error kinds are outside the model, where any non-delivered reply is a non-grant)
- **Status**: FALSE POSITIVE (protocol behavior) — documentation-only inconsistency
- **Severity**: Low (documentation)
- **Source revision**: `artifact/` HEAD `3ab6cdd`

## Claim examined

`openraft/src/docs/protocol/pre_vote.md:58-62` ("Backward compatibility"): the default `RaftNetworkV2::pre_vote` "returns `Unreachable`" and "A node treats an `Unreachable` Pre-Vote response as a grant".

## Evidence

- `openraft/src/network/v2/network.rs` (`pre_vote` default) returns `Ok(VoteResponse::new(rpc.vote, None, true))` — a synthesized grant, not `Unreachable`; its doc comment says an implementor that cannot reach the target must return `Err`, "which the caller does **not** count as a grant".
- `openraft/src/core/raft_core.rs:1376-1382, 1460-1470` (`spawn_parallel_vote_requests`): every `Err` (including `Unreachable`) is logged and dropped; only `Ok(resp)` produces a `PreVoteResponse` notification.
- Test `tests/tests/elect/t12_pre_vote.rs: pre_vote_unreachable_peer_is_not_a_grant` asserts that an isolated node whose peers return `Unreachable` does not inflate its term. Executed on the updated tree: `spec/output/baseline-new-elect.log` → `ok`.
- Model: `PreVoteResp` exists only for replies actually produced by `HandlePreVoteRequest`; dropped/failed replies are `DropMessage`, which never grants.

## Reproduction attempt

Level 0 (public API): the repository's own integration test above was run unmodified (`cargo test -p tests --test elect`): 8/8 pass, including `pre_vote_unreachable_peer_is_not_a_grant`. The implemented behavior is the safe one (no synthesized quorum for a partitioned node).

## Verdict

The implementation does not treat `Unreachable` as a grant; only the prose in `pre_vote.md` is stale (it describes the default `pre_vote` as returning `Unreachable`, while it returns a granting `Ok`). No consumer-visible protocol consequence → FALSE POSITIVE for a protocol defect. Recommendation: update `pre_vote.md` to say the default implementation synthesizes a granting response and that transport errors (including `Unreachable`) are never grants.
