# Confirmation — CR-1: `pre_vote.md` backward-compatibility paragraph contradicts the implemented transport-error semantics

- **Source**: code review (defect ledger D-U2); not model-checked (transport framing/serialization is
  outside the model scope, `/work/model-scope.md` "Exclusions").
- **Revision**: artifact `update` 3ab6cdd.
- **Status**: **FALSE POSITIVE** as an implementation defect (documentation-only inconsistency; the code
  behavior is the intended one). A documentation correction is recommended.

## Investigation
- Doc claim, `openraft/src/docs/protocol/pre_vote.md:54-63`: the default `RaftNetworkV2::pre_vote`
  "returns `Unreachable`" and "A node treats an `Unreachable` Pre-Vote response as a grant".
- Code: the default `pre_vote` returns `Ok(VoteResponse::new(rpc.vote, None, true))`
  (`openraft/src/network/v2/network.rs:141-161`, `openraft/src/network/vote_trait.rs:28-36`);
  `spawn_parallel_vote_requests` never forwards an `Err` (including `Unreachable`) as a grant
  (`openraft/src/core/raft_core.rs:1459-1471`).
- Intent evidence for the code behavior: comments at `raft_core.rs:1377-1384,1459-1463`
  ("A transport failure is not a grant ... otherwise a fully isolated node would synthesize a quorum
  and inflate its term"), `network/v2/network.rs:148-155`, `config/config.rs:417-420`, and the test
  `tests/tests/elect/t12_pre_vote.rs::pre_vote_unreachable_peer_is_not_a_grant`.

## Observation (Level 0, shipped tests on the update revision)
Command: `RUSTUP_TOOLCHAIN=nightly-2026-03-01 timeout 10m cargo test -p tests --test elect t12_pre_vote -- --test-threads=1`
(log `spec/repro/CR-1-t12-pre-vote.log`):
```
test t12_pre_vote::pre_vote_unreachable_peer_is_not_a_grant ... ok
test t12_pre_vote::pre_vote_elects_new_leader_after_leader_isolated ... ok
test result: ok. 6 passed; 0 failed
```
An `Unreachable` Pre-Vote reply is not counted as a grant, exactly as the code comments and test intend;
networks that do not implement `pre_vote` still progress through the default granting implementation, so
the compatibility goal stated by the paragraph holds through a different mechanism. No consumer of the
code observes a wrong outcome; only the prose is stale.

## Verdict
FALSE POSITIVE (no implementation defect). Recommendation: rewrite `pre_vote.md` "Backward
compatibility" to say the default implementation synthesizes a grant and that transport errors are
never grants.
