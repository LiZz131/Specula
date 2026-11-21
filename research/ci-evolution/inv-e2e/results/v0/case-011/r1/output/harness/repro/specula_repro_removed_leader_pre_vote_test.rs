//! Specula MC-2 reproduction (engine level, deterministic).
//!
//! An operator requests a cautious election on the leader
//! (`trigger().elect(true)` → voter check passes → `pre_elect()`,
//! core/raft_core.rs:1683-1691). The leader then removes itself from the voter
//! set (joint, commit, uniform). A late granting Pre-Vote response for the round
//! is delivered under RaftCore's filter (pre_candidate present, equal leader id,
//! raft_core.rs:1803-1820) and `handle_pre_vote_resp()` calls `elect()` on a node
//! that is no longer a voter, although every other election path checks
//! `is_voter` (raft_core.rs:1683-1686, 1971-1974).
//! Asserts the expected behavior: a non-voter does not start an election.
//!
//! Install: copy to openraft/src/engine/tests/ and add
//! `mod specula_repro_removed_leader_pre_vote_test;` to `mod tests` in
//! openraft/src/engine/mod.rs.

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
use crate::entry::payload::EntryPayload;
use crate::raft::VoteResponse;
use crate::type_config::TypeConfigExt;
use crate::type_config::alias::StoredMembershipOf;
use crate::utime::Leased;

fn membership(parts: Vec<std::collections::BTreeSet<u64>>) -> Membership<u64, ()> {
    Membership::<u64, ()>::new_with_defaults(parts, [])
}

#[test]
fn specula_repro_removed_leader_pre_vote_does_not_elect_non_voter() -> anyhow::Result<()> {
    let mut eng = Engine::<UTConfig>::testing_default(1);
    eng.state.enable_validation(false);
    eng.config.id = 1;
    let m = Arc::new(StoredMembershipOf::<UTConfig>::new(
        Some(log_id(1, 1, 1)),
        membership(vec![btreeset! {1,2,3}]),
    ));
    eng.state.membership_state = MembershipState::new(m.clone(), m);
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, 1)]);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::from_millis(500), Vote::new_committed(2, 1));
    eng.state.server_state = ServerState::Leader;
    eng.testing_new_leader();
    eng.output.take_commands();

    // trigger().elect(true) on the leader: is_voter(1) holds, pre_elect().
    assert!(eng.state.membership_state.effective().is_voter(&1));
    eng.pre_elect();
    eng.output.take_commands();
    let probe = *eng.pre_candidate_ref().expect("pre-vote round started").vote_ref();
    assert_eq!(Vote::new(3, 1), probe);

    // The leader removes itself: joint {1,2,3}/{2,3}, commit, then uniform {2,3}.
    eng.try_leader_handler()?.leader_append_entries([EntryPayload::Membership(membership(vec![
        btreeset! {1,2,3},
        btreeset! {2,3},
    ]))]);
    eng.state.update_local_committed(&Some(log_id(2, 1, 2)));
    eng.try_leader_handler()?.leader_append_entries([EntryPayload::Membership(membership(vec![btreeset! {2,3}]))]);
    eng.output.take_commands();
    assert!(!eng.state.membership_state.effective().is_voter(&1), "node 1 is no longer a voter");

    let delivered = eng.pre_candidate_ref().map(|pc| pc.vote_ref().leader_id == probe.leader_id).unwrap_or(false);
    println!("pre-vote response delivered by runtime filter: {}", delivered);
    if delivered {
        eng.handle_pre_vote_resp(2, VoteResponse::new(Vote::new_committed(2, 1), Some(log_id(1, 1, 1)), true));
    }
    println!(
        "after late pre-vote response: is_voter={} server_state={:?} vote={} candidate={} leader={}",
        eng.state.membership_state.effective().is_voter(&1),
        eng.state.server_state,
        eng.state.vote_ref(),
        eng.candidate_ref().is_some(),
        eng.leader_ref().is_some()
    );

    assert!(eng.candidate_ref().is_none(), "a removed (non-voter) node must not start an election");
    assert_eq!(Vote::new_committed(2, 1), *eng.state.vote_ref());
    Ok(())
}
