//! Specula old-version control (baseline ce863f4). Evaluates the baseline
//! leader commit rule of LeaderState::calc_commit_log_id/get_match_log_ids
//! (core/replication.rs:183-220 in this tree) on the same acknowledgement state
//! that the updated Engine reaches in the harness scenario
//! `specula_trace_leader_membership_change_then_acks`.
use std::collections::BTreeMap;

use maplit::btreeset;

use crate::LeaderId;
use crate::LogId;
use crate::Membership;

fn lid(term: u64, node_id: u64, index: u64) -> LogId<u64> {
    LogId::<u64> { leader_id: LeaderId { term, node_id }, index }
}

#[test]
fn specula_control_old_commit_rule_after_joint_append() -> anyhow::Result<()> {
    let m123 = Membership::<u64>::new(vec![btreeset! {1,2,3}], None);
    let joint = m123.next_safe(btreeset! {1,3}, false)?;
    let leader_vote_id = LeaderId { term: 1, node_id: 2 };
    let leader_last = lid(1, 2, 2); // blank at 1, joint membership at 2
    let matched: BTreeMap<u64, LogId<u64>> = [(1, lid(1, 2, 1)), (3, lid(1, 2, 2))].into_iter().collect();
    let committed = Some(lid(1, 2, 1));

    // get_match_log_ids (baseline): leader uses its own last_log_id, others
    // their replication matched value, filtered to the current leader id.
    let mut res = BTreeMap::new();
    for id in joint.voter_ids() {
        let m = if id == 2 { Some(leader_last) } else { matched.get(&id).cloned() };
        if let Some(log_id) = m {
            if log_id.leader_id == leader_vote_id {
                res.insert(id, log_id);
            }
        }
    }
    // calc_commit_log_id (baseline)
    let gm = joint.greatest_majority_value(&res).cloned();
    let commit = std::cmp::max(gm, committed);
    println!("SPECULA_CONTROL joint={:?} values={:?} greatest_majority={:?} commit={:?}",
             joint.get_joint_config(), res, gm, commit);
    Ok(())
}
