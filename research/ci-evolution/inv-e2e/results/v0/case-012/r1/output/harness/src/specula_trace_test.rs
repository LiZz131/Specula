//! Specula harness-only scenarios. They drive real Engine code paths and make no
//! assertion about the protocol outcome; the emitted trace is the evidence.

use std::sync::Arc;

use maplit::btreeset;

use crate::core::ServerState;
use crate::engine::Engine;
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

fn lid(term: u64, node_id: u64, index: u64) -> LogId<u64> {
    LogId::<u64> {
        leader_id: LeaderId { term, node_id },
        index,
    }
}

fn blank() -> Entry<Foo> {
    Entry {
        log_id: LogId::default(),
        payload: EntryPayload::<Foo>::Blank,
    }
}

/// Prior V0 scenario (unchanged): single-voter election fast path.
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

/// Update scenarios U1+U3 (derived from the update's new leader commit path):
/// an established leader of a 3-voter cluster writes its blank entry, one
/// follower acknowledges it, the leader appends the next safe membership toward
/// goal {1,3} (Engine::leader_append_entries -> update_effective_membership ->
/// VecProgress::upgrade_quorum_set), and then the other follower acknowledges up
/// to the membership entry (Engine::update_progress). No outcome is asserted.
#[test]
fn specula_trace_leader_membership_change_then_acks() -> anyhow::Result<()> {
    let m123 = Membership::<u64>::new(vec![btreeset! {1,2,3}], None);
    let initial = lid(0, 0, 0);

    let mut eng = Engine::<u64>::default();
    eng.id = 2;
    eng.state.vote = Vote::new_committed(1, 2);
    eng.state.log_ids.append(initial);
    eng.state.committed = Some(initial);
    let em = Arc::new(EffectiveMembership::new(Some(initial), m123.clone()));
    eng.state.membership_state.committed = em.clone();
    eng.state.membership_state.effective = em;
    eng.state.server_state = ServerState::Leader;
    eng.state.new_leader();

    // LeaderState::run writes the blank entry of the new term.
    eng.leader_append_entries(&mut [blank()]);
    // Replication stream of node 1 reports it matched the blank entry.
    eng.update_progress(1, Some(lid(1, 2, 1)));

    // LeaderState::change_membership: next safe config toward {1,3}.
    let next = m123.next_safe(btreeset! {1,3}, false)?;
    eng.leader_append_entries(&mut [Entry {
        log_id: LogId::default(),
        payload: EntryPayload::<Foo>::Membership(next),
    }]);

    // Replication stream of node 3 reports it matched the membership entry.
    eng.update_progress(3, Some(lid(1, 2, 2)));

    tracing::info!(committed = ?eng.state.committed, "specula scenario end");
    Ok(())
}
