//! Specula code observation for MC-1, voter-adding joint config (not part of run.sh).
use std::sync::Arc;

use maplit::btreeset;

use crate::engine::Engine;
use crate::raft::VoteResponse;
use crate::EffectiveMembership;
use crate::Entry;
use crate::EntryPayload;
use crate::LeaderId;
use crate::LogId;
use crate::Membership;
use crate::Vote;

crate::declare_raft_types!(
    pub(crate) Foo: D=(), R=(), NodeId=u64
);

fn log_id(term: u64, node_id: u64, index: u64) -> LogId<u64> {
    LogId::<u64> { leader_id: LeaderId { term, node_id }, index }
}

/// Voters {1,2,3}, learners {4,5}; leader 2 (vote from 1) commits index 1 with
/// node 1, writes next_safe joint [{1,2,3},{1,2,3,4,5}] at index 2, and only
/// learner 4 acknowledges index 2.  Group {1,2,3} then has one holder (2), so
/// index 2 must not be committed.
#[test]
fn specula_observe_add_voters_joint_commit() {
    let m = Membership::<u64>::new(vec![btreeset! {1,2,3}], Some(btreeset! {4,5}));
    let mut eng = Engine::<u64> { id: 2, ..Default::default() };
    eng.state.log_ids.append(log_id(0, 0, 0));
    eng.state.committed = Some(log_id(0, 0, 0));
    eng.state.membership_state.committed = Arc::new(EffectiveMembership::new(Some(log_id(0, 0, 0)), m.clone()));
    eng.state.membership_state.effective = Arc::new(EffectiveMembership::new(Some(log_id(0, 0, 0)), m));
    eng.elect();
    eng.handle_vote_resp(1, VoteResponse { vote: Vote::new(1, 2), vote_granted: true, last_log_id: Some(log_id(0, 0, 0)) });
    assert!(eng.state.vote.committed);

    eng.leader_append_entries(&mut [Entry { log_id: log_id(0, 0, 0), payload: EntryPayload::<Foo>::Blank }]);
    eng.update_progress(1, Some(log_id(1, 2, 1)));
    assert_eq!(Some(log_id(1, 2, 1)), eng.state.committed);

    let joint = Membership::<u64>::new(vec![btreeset! {1,2,3}, btreeset! {1,2,3,4,5}], None);
    eng.leader_append_entries(&mut [Entry { log_id: log_id(0, 0, 0), payload: EntryPayload::<Foo>::Membership(joint) }]);
    eng.update_progress(4, Some(log_id(1, 2, 2)));

    println!("SPECULA_OBSERVED committed={:?}", eng.state.committed);
    assert_eq!(
        Some(log_id(1, 2, 1)),
        eng.state.committed,
        "index 2 is held by {{2,4}} only; group {{1,2,3}} has no majority, so it must not be committed"
    );
}
