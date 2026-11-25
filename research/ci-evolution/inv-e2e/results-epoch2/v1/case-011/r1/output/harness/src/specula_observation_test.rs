//! Specula code observations for model-checking findings (test-only).
//!
//! These tests drive the real `Engine` handlers of several nodes in-process,
//! delivering each produced request/response by hand exactly as `RaftCore`
//! would (spawn_parallel_vote_requests -> Notification::{Pre,}VoteResponse ->
//! does_{pre_,}candidate_vote_match -> handle_{pre_,}vote_resp). Each test
//! prints one JSON line `{"observation": ..., ...}` with what the engines did.
//! They assert the *observed current behaviour* so that a change in behaviour
//! is visible as a test failure.

use std::collections::BTreeSet;
use std::sync::Arc;
use std::time::Duration;

use maplit::btreeset;
use serde_json::json;

use crate::Membership;
use crate::MembershipState;
use crate::Vote;
use crate::core::ServerState;
use crate::engine::Command;
use crate::engine::Engine;
use crate::engine::LogIdList;
use crate::engine::testing::UTConfig;
use crate::engine::testing::log_id;
use crate::raft::VoteRequest;
use crate::raft::VoteResponse;
use crate::raft_state::LogStateReader;
use crate::type_config::TypeConfigExt;
use crate::type_config::alias::StoredMembershipOf;
use crate::utime::Leased;

fn engine(id: u64, voters: BTreeSet<u64>, last_log_index: u64, last_log_leader: u64, vote: Vote<crate::engine::testing::UTLeaderId>) -> Engine<UTConfig> {
    let mut eng = Engine::testing_default(id);
    eng.state.enable_validation(false);
    eng.config.id = id;
    let m = Arc::new(StoredMembershipOf::<UTConfig>::new(
        Some(log_id(1, 1, 1)),
        Membership::new_with_defaults(vec![voters], []),
    ));
    eng.state.membership_state = MembershipState::new(m.clone(), m);
    eng.state.log_ids = LogIdList::new(None, [log_id(1, last_log_leader, last_log_index)]);
    // Lease already expired (Duration::ZERO), as after the leader went away.
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, vote);
    eng.state.server_state = ServerState::Follower;
    eng.output.take_commands();
    eng
}

fn sent_pre_vote(eng: &mut Engine<UTConfig>) -> Option<VoteRequest<UTConfig>> {
    eng.output.take_commands().into_iter().find_map(|c| match c {
        Command::SendPreVote { vote_req } => Some(vote_req),
        _ => None,
    })
}

fn sent_vote(cmds: &[Command<UTConfig>]) -> Option<VoteRequest<UTConfig>> {
    cmds.iter().find_map(|c| match c {
        Command::SendVote { vote_req } => Some(vote_req.clone()),
        _ => None,
    })
}

/// MC-1 code observation (Scenario U-S2). Live voters {2,3} of {1,2,3}; node 1
/// (the old leader) is down. Node 2 holds the longest log but the lower vote
/// (1,1,committed); node 3 holds the higher vote (2,3) but a shorter log.
/// Every Pre-Vote round of either node is rejected and neither node ever
/// changes its vote or emits SaveVote/SendVote, however many rounds run.
#[test]
fn specula_observe_prevote_livelock() -> anyhow::Result<()> {
    let voters = btreeset! {1, 2, 3};
    let mut x = engine(2, voters.clone(), 2, 1, Vote::new_committed(1, 1));
    let mut y = engine(3, voters.clone(), 1, 1, Vote::new(2, 3));
    y.state.server_state = ServerState::Candidate;
    y.new_candidate(*y.state.vote_ref());
    y.output.take_commands();

    let (x_vote0, y_vote0) = (*x.state.vote_ref(), *y.state.vote_ref());
    let mut rounds = 0;
    let mut real_elections = 0;
    for _ in 0..20 {
        // node 2 pre-votes; node 3 answers; node 2 tallies the answer.
        x.pre_elect();
        let req = sent_pre_vote(&mut x).expect("node 2 sends a pre-vote");
        let round = req.vote;
        let resp = y.handle_pre_vote_req(req);
        assert!(!resp.vote_granted, "node 3 rejects node 2 (vote order)");
        if x.pre_candidate_ref().map(|p| *p.vote_ref()) == Some(round) {
            x.handle_pre_vote_resp(3, resp);
        }
        real_elections += x.output.take_commands().iter().filter(|c| matches!(c, Command::SendVote { .. })).count();
        y.output.take_commands();

        // node 3 pre-votes; node 2 answers; node 3 tallies the answer.
        y.pre_elect();
        let req = sent_pre_vote(&mut y).expect("node 3 sends a pre-vote");
        let round = req.vote;
        let resp = x.handle_pre_vote_req(req);
        assert!(!resp.vote_granted, "node 2 rejects node 3 (last log)");
        if y.pre_candidate_ref().map(|p| *p.vote_ref()) == Some(round) {
            y.handle_pre_vote_resp(2, resp);
        }
        real_elections += y.output.take_commands().iter().filter(|c| matches!(c, Command::SendVote { .. })).count();
        x.output.take_commands();
        rounds += 1;
    }
    assert_eq!(0, real_elections);
    assert_eq!(x_vote0, *x.state.vote_ref());
    assert_eq!(y_vote0, *y.state.vote_ref());
    println!(
        "{}",
        json!({"observation": "prevote_livelock", "rounds": rounds, "real_elections": real_elections,
               "node2_vote": x.state.vote_ref().to_string(), "node3_vote": y.state.vote_ref().to_string(),
               "node2_last_log": x.state.last_log_id().map(|l| l.to_string()),
               "node3_last_log": y.state.last_log_id().map(|l| l.to_string())})
    );
    Ok(())
}

/// MC-1 attribution control: the same two live engines with Pre-Vote disabled
/// (the pre-update tick path, Engine::elect). Node 2 learns node 3's higher
/// vote from the rejected real vote response (handle_vote_resp adopts it),
/// re-elects at the next term, and node 3 grants: a leader is elected.
#[test]
fn specula_observe_old_path_recovers() -> anyhow::Result<()> {
    let voters = btreeset! {1, 2, 3};
    let mut x = engine(2, voters.clone(), 2, 1, Vote::new_committed(1, 1));
    let mut y = engine(3, voters.clone(), 1, 1, Vote::new(2, 3));
    y.state.server_state = ServerState::Candidate;
    y.new_candidate(*y.state.vote_ref());
    y.output.take_commands();

    let mut attempts = 0;
    while x.state.server_state != ServerState::Leader && attempts < 5 {
        attempts += 1;
        x.elect();
        let cmds = x.output.take_commands();
        let req = sent_vote(&cmds).expect("node 2 sends a vote request");
        // SaveVote is awaited, then the runtime feeds the local grant.
        x.handle_vote_resp(2, VoteResponse::new(req.vote, None, true));
        x.output.take_commands();
        let resp = y.handle_vote_req(req);
        y.output.take_commands();
        x.handle_vote_resp(3, resp);
        x.output.take_commands();
    }
    assert_eq!(ServerState::Leader, x.state.server_state);
    println!(
        "{}",
        json!({"observation": "old_path_recovers", "attempts": attempts,
               "node2_vote": x.state.vote_ref().to_string(), "node2_state": format!("{:?}", x.state.server_state)})
    );
    Ok(())
}

/// MC-2 code observation (Scenario U-S3): a Candidate whose tick runs
/// pre_elect, then wins its real election, keeps the pre-candidate; the late
/// Pre-Vote quorum starts a new election on the established Leader.
#[test]
fn specula_observe_leader_demoted_by_stale_prevote() -> anyhow::Result<()> {
    let voters = btreeset! {1, 2, 3};
    let mut n = engine(1, voters, 1, 1, Vote::new_committed(0, 2));
    n.elect();
    let cmds = n.output.take_commands();
    let req = sent_vote(&cmds).expect("vote request");
    n.handle_vote_resp(1, VoteResponse::new(req.vote, None, true));
    n.output.take_commands();
    // Election timer fires again while the real election is still open.
    n.pre_elect();
    let pre_req = sent_pre_vote(&mut n).expect("pre-vote request");
    // Real grant from node 2 arrives: the node becomes Leader.
    n.handle_vote_resp(2, VoteResponse::new(req.vote, Some(log_id(1, 1, 1)), true));
    n.output.take_commands();
    assert_eq!(ServerState::Leader, n.state.server_state);
    let leader_vote = *n.state.vote_ref();
    let pre_candidate_after_establish = n.pre_candidate_ref().is_some();
    // Node 3 had granted the pre-vote (its vote (1,1) <= (2,1), no lease).
    // RaftCore forwards it: pre_candidate exists and the leader id matches.
    assert_eq!(Some(pre_req.vote), n.pre_candidate_ref().map(|p| *p.vote_ref()));
    n.handle_pre_vote_resp(3, VoteResponse::new(req.vote, Some(log_id(1, 1, 1)), true));
    let cmds = n.output.take_commands();
    println!(
        "{}",
        json!({"observation": "leader_demoted_by_stale_prevote",
               "pre_candidate_after_establish": pre_candidate_after_establish,
               "leader_vote": leader_vote.to_string(),
               "vote_after": n.state.vote_ref().to_string(),
               "state_after": format!("{:?}", n.state.server_state),
               "send_vote_emitted": sent_vote(&cmds).is_some()})
    );
    assert_eq!(ServerState::Candidate, n.state.server_state);
    assert!(n.state.vote_ref().leader_id.term > leader_vote.leader_id.term);
    Ok(())
}
