//! Specula update-focused scenarios (harness-only test file).
//!
//! Derived from the visible diff: leader commit is now computed by
//! `Engine::update_progress` over `Leader.progress` (a `VecProgress` keyed by the
//! effective membership), and a membership entry upgrades that progress with
//! `upgrade_quorum_set` inside `leader_append_entries`.
//!
//! The scenario drives only real Engine entry points in the order the runtime
//! uses them: `elect` + `handle_vote_resp` (election), `leader_append_entries`
//! (LeaderState::write_entry), and `update_progress` (LeaderState::
//! handle_update_matched, which calls it only for matched > committed).

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
    LogId::<u64> {
        leader_id: LeaderId { term, node_id },
        index,
    }
}

fn blank() -> Entry<Foo> {
    Entry {
        log_id: log_id(0, 0, 0),
        payload: EntryPayload::<Foo>::Blank,
    }
}

fn membership(m: Membership<u64>) -> Entry<Foo> {
    Entry {
        log_id: log_id(0, 0, 0),
        payload: EntryPayload::<Foo>::Membership(m),
    }
}

/// An initialized node 2 of a 3-voter cluster {1,2,3}: index 0 holds the
/// initial membership entry (0,0,0) written by `Engine::initialize`
/// (raft_types.rs requires the zero-th log id to be (0,0,0)).  Node 2 is then
/// elected with a grant from node 1.
fn elected_leader_2() -> Engine<u64> {
    let mut eng = Engine::<u64> { id: 2, ..Default::default() };
    let m123 = Membership::<u64>::new(vec![btreeset! {1,2,3}], None);
    eng.state.log_ids.append(log_id(0, 0, 0));
    eng.state.committed = Some(log_id(0, 0, 0));
    eng.state.membership_state.committed = Arc::new(EffectiveMembership::new(Some(log_id(0, 0, 0)), m123.clone()));
    eng.state.membership_state.effective = Arc::new(EffectiveMembership::new(Some(log_id(0, 0, 0)), m123));

    eng.elect();
    eng.handle_vote_resp(1, VoteResponse {
        vote: Vote::new(1, 2),
        vote_granted: true,
        last_log_id: Some(log_id(0, 0, 0)),
    });
    assert!(eng.state.vote.committed, "node 2 must be leader");
    eng
}

/// Update scenario U1: leader 2 commits a blank entry with node 1, proposes the
/// next_safe joint config that removes itself ([{1,2,3},{1,3}]), and node 3
/// (only) acknowledges the joint membership entry (index 2).
///
/// Requirement (joint quorum, guide/src/dynamic-membership.md): index 2 may be
/// committed only when a majority of {1,2,3} AND of {1,3} hold it.  Here only
/// {2,3} hold index 2, so {1,3} is not satisfied.
///
/// This harness test records the observed commit; it does not assert the
/// requirement so that the trace is collected either way.  The requirement is
/// asserted separately by `specula_observe_joint_commit_requires_both_groups`.
#[test]
fn specula_update_joint_commit_order() -> anyhow::Result<()> {
    let mut eng = elected_leader_2();

    // LeaderState::run writes the initial blank entry -> index 1.
    eng.leader_append_entries(&mut [blank()]);
    // Node 1 acknowledges index 1 -> committed by {1,2}.
    eng.update_progress(1, Some(log_id(1, 2, 1)));
    assert_eq!(Some(log_id(1, 2, 1)), eng.state.committed);

    // change_membership({1,3}) writes next_safe = joint [{1,2,3},{1,3}] -> index 2.
    let joint = Membership::<u64>::new(vec![btreeset! {1,2,3}, btreeset! {1,3}], None);
    eng.leader_append_entries(&mut [membership(joint)]);

    // Node 3 acknowledges index 2 (handle_update_matched: matched (1,2) > committed (1,1)).
    eng.update_progress(3, Some(log_id(1, 2, 2)));

    println!("SPECULA_OBSERVED committed={:?}", eng.state.committed);
    Ok(())
}

/// Requirement check for scenario U1 (expected to pass on a correct
/// implementation; run separately as code observation).
#[test]
fn specula_observe_joint_commit_requires_both_groups() -> anyhow::Result<()> {
    let mut eng = elected_leader_2();
    eng.leader_append_entries(&mut [blank()]);
    eng.update_progress(1, Some(log_id(1, 2, 1)));
    let joint = Membership::<u64>::new(vec![btreeset! {1,2,3}, btreeset! {1,3}], None);
    eng.leader_append_entries(&mut [membership(joint)]);
    eng.update_progress(3, Some(log_id(1, 2, 2)));

    assert_eq!(
        Some(log_id(1, 2, 1)),
        eng.state.committed,
        "index 2 is held by {{2,3}} only; group {{1,3}} has no majority, so it must not be committed"
    );
    Ok(())
}

/// Update scenario U2: uniform 3-voter cluster, ordinary replication through
/// update_progress (no membership change).  Expected: commit follows the
/// majority of acknowledged log ids.
#[test]
fn specula_update_uniform_commit() -> anyhow::Result<()> {
    let mut eng = elected_leader_2();
    eng.leader_append_entries(&mut [blank()]);
    eng.update_progress(3, Some(log_id(1, 2, 1)));
    eng.leader_append_entries(&mut [blank()]);
    eng.leader_append_entries(&mut [blank()]);
    eng.update_progress(1, Some(log_id(1, 2, 2)));
    eng.update_progress(3, Some(log_id(1, 2, 3)));
    eng.update_progress(1, Some(log_id(1, 2, 3)));
    println!("SPECULA_OBSERVED committed={:?}", eng.state.committed);
    Ok(())
}

/// Update scenario U3 (follower boundary): commit does not advance while the
/// effective membership is already covered by the local commit.  The updated
/// RaftState::update_committed promotes committed membership only when commit
/// advances (raft_state.rs:122-137); the old follower path promoted it
/// unconditionally (old engine_impl.rs:370-372).  Records the observed state.
#[test]
fn specula_follower_commit_no_advance() -> anyhow::Result<()> {
    let m01 = Membership::<u64>::new(vec![btreeset! {0,1}], None);
    let m23 = Membership::<u64>::new(vec![btreeset! {2,3}], None);
    let mut eng = Engine::<u64>::default();
    eng.state.committed = Some(log_id(2, 1, 3));
    eng.state.membership_state.committed = Arc::new(EffectiveMembership::new(Some(log_id(1, 1, 1)), m01));
    eng.state.membership_state.effective = Arc::new(EffectiveMembership::new(Some(log_id(2, 1, 3)), m23));

    eng.follower_commit_entries(Some(log_id(2, 1, 3)), Some(log_id(2, 1, 3)), &Vec::<Entry<Foo>>::new());

    println!(
        "SPECULA_OBSERVED committed={:?} committed_membership={:?}",
        eng.state.committed, eng.state.membership_state.committed.log_id
    );
    Ok(())
}
