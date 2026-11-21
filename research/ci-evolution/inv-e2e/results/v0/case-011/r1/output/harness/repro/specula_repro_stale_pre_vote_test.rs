//! Specula MC-1 reproduction (engine level, deterministic).
//!
//! Drives the real updated `Engine` through the counterexample suffix:
//! Candidate(t) -> pre_elect() [probe t+1] -> handle_vote_resp() establishes
//! leader at t -> a granting Pre-Vote response for the probe is delivered under
//! the same filter RaftCore applies (pre_candidate present and leader id equal,
//! core/raft_core.rs:1803-1820). Asserts the expected behavior: the established
//! leader keeps leadership and its committed vote.
//!
//! Install: copy to openraft/src/engine/tests/ and add
//! `mod specula_repro_stale_pre_vote_test;` to `mod tests` in
//! openraft/src/engine/mod.rs; run
//! `cargo test -p openraft --lib specula_repro_stale_pre_vote -- --nocapture`.

use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;

use crate::Membership;
use crate::MembershipState;
use crate::Vote;
use crate::core::ServerState;
use crate::engine::Engine;
use crate::engine::LogIdList;
use crate::engine::testing::UTConfig;
use crate::engine::testing::log_id;
use crate::raft::VoteResponse;
use crate::type_config::TypeConfigExt;
use crate::type_config::alias::StoredMembershipOf;
use crate::utime::Leased;

#[test]
fn specula_repro_stale_pre_vote_does_not_demote_established_leader() -> anyhow::Result<()> {
    let mut eng = Engine::<UTConfig>::testing_default(1);
    eng.state.enable_validation(false);
    eng.config.id = 1;
    let m = Arc::new(StoredMembershipOf::<UTConfig>::new(
        Some(log_id(1, 1, 1)),
        Membership::<u64, ()>::new_with_defaults(vec![btreeset! {1,2,3}], []),
    ));
    eng.state.membership_state = MembershipState::new(m.clone(), m);
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, 1)]);

    // Candidate at term 2 whose own vote is already persisted and self-granted.
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref()).grant_by(&1);
    eng.output.take_commands();

    // Election timer fires while the election is in flight (raft_core.rs:1959-2036).
    eng.pre_elect();
    eng.output.take_commands();
    let probe = *eng.pre_candidate_ref().expect("pre-vote round started").vote_ref();
    assert_eq!(Vote::new(3, 1), probe);

    // The delayed vote response for term 2 arrives: leader established.
    eng.handle_vote_resp(2, VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true));
    eng.output.take_commands();
    assert_eq!(ServerState::Leader, eng.state.server_state);
    assert_eq!(Vote::new_committed(2, 1), *eng.state.vote_ref());

    // A late granting Pre-Vote response for the superseded round, delivered
    // only if RaftCore's filter would deliver it.
    let delivered = eng.pre_candidate_ref().map(|pc| pc.vote_ref().leader_id == probe.leader_id).unwrap_or(false);
    println!("pre-vote response delivered by runtime filter: {}", delivered);
    if delivered {
        eng.handle_pre_vote_resp(2, VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true));
    }
    println!(
        "after late pre-vote response: server_state={:?} vote={} candidate={} leader={}",
        eng.state.server_state,
        eng.state.vote_ref(),
        eng.candidate_ref().is_some(),
        eng.leader_ref().is_some()
    );

    assert_eq!(
        (ServerState::Leader, Vote::new_committed(2, 1)),
        (eng.state.server_state, *eng.state.vote_ref()),
        "a stale Pre-Vote round must not make an established leader start a new election"
    );
    Ok(())
}
