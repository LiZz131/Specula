//! Code observation (new revision aa05a38): same fixtures as the V1 observation test.
use std::sync::Arc;
use maplit::btreeset;
use crate::engine::Engine;
use crate::{EffectiveMembership, Entry, EntryPayload, LeaderId, LogId, Membership, Vote};
crate::declare_raft_types!(pub(crate) ObsFoo: D=(), R=(), NodeId=u64);
fn lid(term: u64, node: u64, index: u64) -> LogId<u64> { LogId::new(LeaderId::new(term, node), index) }
fn blank() -> Entry<ObsFoo> { Entry { log_id: lid(1, 1, 1), payload: EntryPayload::Blank } }
fn report(tag: &str, eng: &Engine<u64>) {
    println!("SPECULA-OBS {} committed={:?} committed_mem={:?} effective_mem={:?}", tag,
        eng.state.committed, eng.state.membership_state.committed.log_id, eng.state.membership_state.effective.log_id);
}
#[test]
fn specula_observe_fast_commit_upto_membership() {
    let mut eng = Engine::<u64> { id: 1, ..Default::default() };
    eng.state.vote = Vote::new_committed(3, 1);
    eng.state.log_ids.append(lid(1, 1, 1));
    eng.state.log_ids.append(lid(2, 1, 3));
    eng.state.membership_state.committed = Arc::new(EffectiveMembership::new(Some(lid(1, 1, 1)), Membership::new(vec![btreeset! {0,1}], None)));
    eng.state.membership_state.effective = Arc::new(EffectiveMembership::new(Some(lid(2, 1, 3)), Membership::new(vec![btreeset! {1}], None)));
    eng.state.new_leader();
    eng.leader_append_entries(&mut [blank(), Entry { log_id: lid(1, 1, 1), payload: EntryPayload::Membership(Membership::new(vec![btreeset! {3,4}], None)) }, blank()]);
    report("fast_commit_upto_membership", &eng);
}
#[test]
fn specula_observe_follower_no_advance() {
    let mut eng = Engine::<u64> { id: 2, ..Default::default() };
    eng.state.log_ids.append(lid(1, 1, 1));
    eng.state.log_ids.append(lid(2, 1, 3));
    eng.state.committed = Some(lid(2, 1, 3));
    eng.state.membership_state.committed = Arc::new(EffectiveMembership::new(Some(lid(1, 1, 1)), Membership::new(vec![btreeset! {0,1}], None)));
    eng.state.membership_state.effective = Arc::new(EffectiveMembership::new(Some(lid(2, 1, 3)), Membership::new(vec![btreeset! {2,3}], None)));
    eng.follower_commit_entries(Some(lid(2, 1, 3)), Some(lid(2, 1, 3)), &Vec::<Entry<ObsFoo>>::new());
    report("follower_no_advance", &eng);
}
