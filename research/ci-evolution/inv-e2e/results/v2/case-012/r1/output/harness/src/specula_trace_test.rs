//! Specula harness-owned scenarios (instrumentation-only test module).
//! V0: specula_trace_election_single.
//! V1 (update-focused, derived from the visible diff):
//!   specula_trace_leader_lifecycle      elect -> vote response -> leader append ->
//!                                       update_progress (older-term value, commit) ->
//!                                       membership append to joint / uniform
//!                                       (progress quorum-set upgrade, untracked id) ->
//!                                       higher vote (leader data dropped) -> re-elect
//!   specula_trace_follower_commit_no_advance
//!                                       follower_commit_entries without a commit
//!                                       advance while effective <= committed

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
use crate::ServerState;
use crate::Vote;

crate::declare_raft_types!(
    pub(crate) SpeculaFoo: D=(), R=(), NodeId=u64
);

fn lid(term: u64, node_id: u64, index: u64) -> LogId<u64> {
    LogId::new(LeaderId::new(term, node_id), index)
}

fn blank() -> Entry<SpeculaFoo> {
    Entry {
        log_id: lid(0, 0, 0),
        payload: EntryPayload::<SpeculaFoo>::Blank,
    }
}

fn membership_entry(m: Membership<u64>) -> Entry<SpeculaFoo> {
    Entry {
        log_id: lid(0, 0, 0),
        payload: EntryPayload::<SpeculaFoo>::Membership(m),
    }
}

#[test]
fn specula_trace_election_single() -> anyhow::Result<()> {
    let mut engine = Engine::<u64>::default();
    engine.id = 1;
    engine.state.membership_state.effective =
        Arc::new(EffectiveMembership::new(None, Membership::new(vec![btreeset! {1}], None)));

    engine.elect();

    assert!(engine.state.vote.committed);
    assert!(engine.state.server_state.is_leader());
    Ok(())
}

#[test]
fn specula_trace_leader_lifecycle() -> anyhow::Result<()> {
    let m123 = Membership::<u64>::new(vec![btreeset! {1,2,3}], None);
    let joint = Membership::<u64>::new(vec![btreeset! {1,2,3}, btreeset! {1,2}], None);
    let m12 = Membership::<u64>::new(vec![btreeset! {1,2}], None);

    let mut eng = Engine::<u64>::default();
    eng.id = 1;
    // Node 1 followed leader 2 of term 1 and holds its entries 1..=2
    // (index 0 is the initial (0,0,0) entry required by RaftLogId).
    eng.state.log_ids.append(lid(0, 0, 0));
    eng.state.log_ids.append(lid(1, 2, 1));
    eng.state.log_ids.append(lid(1, 2, 2));
    eng.state.committed = Some(lid(1, 2, 1));
    eng.state.membership_state.committed = Arc::new(EffectiveMembership::new(Some(lid(1, 2, 1)), m123.clone()));
    eng.state.membership_state.effective = Arc::new(EffectiveMembership::new(Some(lid(1, 2, 1)), m123));
    eng.state.vote = Vote::new_committed(1, 2);
    eng.state.server_state = ServerState::Follower;

    // Candidate of term 2 with fresh leader data (progress over {1,2,3}).
    eng.elect();
    assert_eq!(ServerState::Candidate, eng.state.server_state);

    // Node 3 grants: {1,3} is a quorum of the progress quorum set.
    eng.handle_vote_resp(3, VoteResponse {
        vote: Vote::new(2, 1),
        vote_granted: true,
        last_log_id: Some(lid(1, 2, 2)),
    });
    assert_eq!(ServerState::Leader, eng.state.server_state);

    // Leader blank entry at index 3; own progress only.
    eng.leader_append_entries(&mut [blank()]);
    assert_eq!(Some(lid(1, 2, 1)), eng.state.committed);

    // An older-term quorum value is not committed.
    eng.update_progress(3, Some(lid(1, 2, 2)));
    assert_eq!(Some(lid(1, 2, 1)), eng.state.committed);

    // Current-term quorum value {1,3} commits index 3.
    eng.update_progress(3, Some(lid(2, 1, 3)));
    assert_eq!(Some(lid(2, 1, 3)), eng.state.committed);

    // Joint membership entry at index 4: progress quorum set upgraded.
    eng.leader_append_entries(&mut [membership_entry(joint)]);
    assert_eq!(Some(lid(2, 1, 3)), eng.state.committed);

    // Node 3 alone cannot satisfy the {1,2} component.
    eng.update_progress(3, Some(lid(2, 1, 4)));
    assert_eq!(Some(lid(2, 1, 3)), eng.state.committed);

    // Node 2 completes both components: commit 4 and promote the joint config.
    eng.update_progress(2, Some(lid(2, 1, 4)));
    assert_eq!(Some(lid(2, 1, 4)), eng.state.committed);

    // Uniform {1,2} entry at index 5: node 3 is no longer tracked.
    eng.leader_append_entries(&mut [membership_entry(m12)]);
    eng.update_progress(3, Some(lid(2, 1, 5)));
    assert_eq!(Some(lid(2, 1, 4)), eng.state.committed);
    eng.update_progress(2, Some(lid(2, 1, 5)));
    assert_eq!(Some(lid(2, 1, 5)), eng.state.committed);

    // A higher vote drops leader data.
    eng.handle_vote_resp(2, VoteResponse {
        vote: Vote::new(3, 2),
        vote_granted: false,
        last_log_id: Some(lid(2, 1, 5)),
    });
    assert_eq!(ServerState::Follower, eng.state.server_state);
    assert!(eng.state.leader.is_none());

    // Re-election creates new leader data over the current effective membership.
    eng.elect();
    eng.handle_vote_resp(2, VoteResponse {
        vote: Vote::new(4, 1),
        vote_granted: true,
        last_log_id: Some(lid(2, 1, 5)),
    });
    assert_eq!(ServerState::Leader, eng.state.server_state);
    Ok(())
}

#[test]
fn specula_trace_follower_commit_no_advance() -> anyhow::Result<()> {
    let m01 = Membership::<u64>::new(vec![btreeset! {0,1}], None);
    let m23 = Membership::<u64>::new(vec![btreeset! {2,3}], None);

    let mut eng = Engine::<u64>::default();
    eng.id = 2;
    eng.state.log_ids.append(lid(1, 1, 1));
    eng.state.log_ids.append(lid(2, 1, 3));
    eng.state.committed = Some(lid(2, 1, 3));
    eng.state.membership_state.committed = Arc::new(EffectiveMembership::new(Some(lid(1, 1, 1)), m01));
    eng.state.membership_state.effective = Arc::new(EffectiveMembership::new(Some(lid(2, 1, 3)), m23));

    // Leader commit equals the local commit: no advance.
    eng.follower_commit_entries(Some(lid(2, 1, 3)), Some(lid(2, 1, 3)), &Vec::<Entry<SpeculaFoo>>::new());
    assert_eq!(Some(lid(2, 1, 3)), eng.state.committed);
    Ok(())
}

#[test]
fn specula_trace_update_effective_membership_to_learner() -> anyhow::Result<()> {
    // Consistent pre-state: committed membership (1) <= effective (3) <= new entry (4).
    let m01 = Membership::<u64>::new(vec![btreeset! {0,1}], None);
    let m23 = Membership::<u64>::new(vec![btreeset! {2,3}], None);
    let m34 = Membership::<u64>::new(vec![btreeset! {3,4}], None);

    let mut eng = Engine::<u64>::default();
    eng.id = 2;
    eng.state.server_state = ServerState::Follower;
    eng.state.log_ids.append(lid(0, 0, 0));
    eng.state.log_ids.append(lid(1, 1, 1));
    eng.state.log_ids.append(lid(2, 1, 3));
    eng.state.log_ids.append(lid(2, 1, 4));
    eng.state.committed = Some(lid(1, 1, 1));
    eng.state.membership_state.committed = Arc::new(EffectiveMembership::new(Some(lid(1, 1, 1)), m01));
    eng.state.membership_state.effective = Arc::new(EffectiveMembership::new(Some(lid(2, 1, 3)), m23));

    eng.update_effective_membership(&lid(2, 1, 4), &m34);
    assert_eq!(ServerState::Learner, eng.state.server_state);
    Ok(())
}
