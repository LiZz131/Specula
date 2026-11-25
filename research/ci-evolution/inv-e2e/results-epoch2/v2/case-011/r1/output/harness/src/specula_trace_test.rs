//! Specula trace harness (rebased onto the Pre-Vote revision).
//!
//! Test-only instrumentation. It invokes real `Engine` transitions directly
//! and records only source-observable abstract state. Between two events of
//! one scenario it executes the queued engine commands the way
//! `RaftCore::run_command` does (`core/raft_core.rs:2273-2304,2339-2344`):
//! the queue is drained (vote saved, vote/pre-vote RPCs spawned, log flushed)
//! and, for a saved non-committed vote with a candidate, the runtime's local
//! `VoteResponse(vote, None, true)` is fed back as its own event.
//!
//! V0 scenarios are kept unchanged except for the extended state capture.

use std::collections::BTreeSet;
use std::fs::OpenOptions;
use std::io::Write;
use std::sync::Arc;
use std::time::Duration;
use std::time::SystemTime;
use std::time::UNIX_EPOCH;

use maplit::btreeset;
use serde_json::Value;
use serde_json::json;

use crate::Membership;
use crate::MembershipState;
use crate::Vote;
use crate::core::ServerState;
use crate::engine::Command;
use crate::engine::CommandName;
use crate::engine::Engine;
use crate::engine::LogIdList;
use crate::engine::testing::UTConfig;
use crate::engine::testing::log_id;
use crate::entry::payload::EntryPayload;
use crate::progress::Progress;
use crate::raft::LogSegment;
use crate::raft::VoteRequest;
use crate::raft::VoteResponse;
use crate::raft_state::LogStateReader;
use crate::type_config::TypeConfigExt;
use crate::type_config::alias::StoredMembershipOf;
use crate::utime::Leased;

type UTVote = Vote<crate::engine::testing::UTLeaderId>;

fn membership(parts: Vec<BTreeSet<u64>>) -> Membership<u64, ()> {
    Membership::new_with_defaults(parts, [])
}

fn stored(index: u64, parts: Vec<BTreeSet<u64>>) -> Arc<StoredMembershipOf<UTConfig>> {
    Arc::new(StoredMembershipOf::<UTConfig>::new(
        Some(log_id(1, 1, index)),
        membership(parts),
    ))
}

fn base_engine(id: u64, parts: Vec<BTreeSet<u64>>, membership_index: u64) -> Engine<UTConfig> {
    let mut eng = Engine::testing_default(id);
    eng.state.enable_validation(false);
    eng.config.id = id;
    let membership = stored(membership_index, parts);
    eng.state.membership_state = MembershipState::new(membership.clone(), membership);
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, membership_index)]);
    eng.state.server_state = ServerState::Follower;
    eng.output.clear_commands();
    eng
}

fn vote_json(v: &UTVote) -> Value {
    json!({
        "term": v.leader_id.term,
        "node": v.leader_id.node_id.to_string(),
        "committed": v.committed,
    })
}

fn log_json(log: Option<&crate::type_config::alias::LogIdOf<UTConfig>>, node: u64) -> Value {
    match log {
        Some(x) => json!({
            "present": true,
            "term": x.leader_id.term,
            "node": x.leader_id.node_id.to_string(),
            "index": x.index,
        }),
        None => json!({"present": false, "term": 0, "node": node.to_string(), "index": 0}),
    }
}

fn parts_json(parts: &[BTreeSet<u64>]) -> Value {
    json!(parts.iter().map(|part| part.iter().map(u64::to_string).collect::<Vec<_>>()).collect::<Vec<_>>())
}

fn config_json(m: &StoredMembershipOf<UTConfig>) -> Value {
    parts_json(m.get_joint_config())
}

fn state_json(eng: &Engine<UTConfig>, crashed: bool) -> Value {
    let candidate = eng.candidate_ref();
    let candidate_vote = candidate.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let grants = candidate
        .map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>())
        .unwrap_or_default();
    let pre = eng.pre_candidate_ref();
    let pre_vote = pre.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let pre_grants =
        pre.map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>()).unwrap_or_default();
    let has_command = |name| eng.output.iter_commands().any(|cmd| cmd.name() == name);
    let (last_update, lease, enabled) = eng.state.vote.lease_info();
    let lease_valid = enabled
        && last_update.is_some()
        && !eng.state.vote.is_expired(UTConfig::<()>::now(), Duration::default())
        && !lease.is_zero();
    let committed = eng.state.membership_state.committed();
    let effective = eng.state.membership_state.effective();
    // Real frozen quorum sets (Candidate::progress().quorum_set()); the
    // effective config is reported when no tracker exists.
    let candidate_config = candidate
        .map(|c| parts_json(c.progress().quorum_set().get_joint_config()))
        .unwrap_or_else(|| config_json(effective));
    let pre_config = pre
        .map(|c| parts_json(c.progress().quorum_set().get_joint_config()))
        .unwrap_or_else(|| config_json(effective));

    json!({
        "role": match eng.state.server_state {
            ServerState::Learner => "Learner",
            ServerState::Follower => "Follower",
            ServerState::Candidate => "Candidate",
            ServerState::Leader => "Leader",
            ServerState::Shutdown => "Follower",
        },
        "vote": vote_json(eng.state.vote_ref()),
        "last_log": log_json(eng.state.last_log_id(), eng.config.id),
        "committed_config": config_json(committed),
        "committed_config_index": committed.log_id().as_ref().map(|x| x.index).unwrap_or(0),
        "effective_config": config_json(effective),
        "effective_config_index": effective.log_id().as_ref().map(|x| x.index).unwrap_or(0),
        "lease_valid": lease_valid,
        "candidate_active": candidate.is_some(),
        "candidate_vote": vote_json(candidate_vote),
        "candidate_config": candidate_config,
        "grants": grants,
        "leader_active": eng.leader_ref().is_some(),
        "save_vote_pending": has_command(CommandName::SaveVote),
        "send_vote_pending": has_command(CommandName::SendVote),
        "append_pending": has_command(CommandName::AppendEntries),
        "seen_greater_log": eng.is_there_greater_log(),
        "crashed": crashed,
        "pre_candidate_active": pre.is_some(),
        "pre_candidate_vote": vote_json(pre_vote),
        "pre_grants": pre_grants,
        "pre_candidate_config": pre_config,
        "send_pre_vote_pending": has_command(CommandName::SendPreVote),
    })
}

fn emit(name: &str, nid: u64, pre: Value, post: Value, args: Value) -> anyhow::Result<()> {
    let path = std::env::var("SPECULA_TRACE_PATH")?;
    let mut out = OpenOptions::new().create(true).append(true).open(path)?;
    let ts = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos().to_string();
    let record = json!({
        "tag": "trace",
        "ts_unix_ns": ts,
        "event": {
            "name": name,
            "nid": nid.to_string(),
            "pre": pre,
            "post": post,
            "args": args,
        }
    });
    serde_json::to_writer(&mut out, &record)?;
    writeln!(&mut out)?;
    Ok(())
}

/// Execute the queued commands as RaftCore::run_command would and return the
/// saved non-committed vote if a candidate is waiting for its local response
/// (core/raft_core.rs:2273-2304).
fn run_commands(eng: &mut Engine<UTConfig>) -> Option<UTVote> {
    let mut local = None;
    for cmd in eng.output.take_commands() {
        if let Command::SaveVote { vote } = cmd {
            if !vote.committed {
                local = Some(vote);
            }
        }
    }
    local
}

fn req_vote_of_send_pre_vote(eng: &Engine<UTConfig>) -> Option<(Value, Value)> {
    eng.output.iter_commands().find_map(|cmd| match cmd {
        Command::SendPreVote { vote_req } => Some((
            vote_json(&vote_req.vote),
            log_json(vote_req.last_log_id.as_ref(), eng.config.id),
        )),
        _ => None,
    })
}

// ---- event wrappers (each captures pre/post around one real Engine call) ----

fn ev_elect(eng: &mut Engine<UTConfig>) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    eng.elect();
    let post = state_json(eng, false);
    emit("StartElection", eng.config.id, pre, post, json!({"transfer": false}))
}

/// `trigger` = "tick" reproduces handle_tick_election's reset_greater_log()
/// before pre_elect() (core/raft_core.rs:2027-2032); "external" is
/// ExternalCommand::Elect { pre_vote: true } (core/raft_core.rs:1683-1690).
fn ev_pre_elect(eng: &mut Engine<UTConfig>, trigger: &str) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    if trigger == "tick" {
        eng.reset_greater_log();
    }
    eng.pre_elect();
    let post = state_json(eng, false);
    let (rv, rl) = req_vote_of_send_pre_vote(eng)
        .unwrap_or_else(|| (vote_json(eng.state.vote_ref()), log_json(eng.state.last_log_id(), eng.config.id)));
    emit(
        "StartPreVote",
        eng.config.id,
        pre,
        post,
        json!({"trigger": trigger, "req_vote": rv, "req_last_log": rl}),
    )
}

fn ev_vote_resp(eng: &mut Engine<UTConfig>, source: u64, resp: VoteResponse<UTConfig>) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    eng.handle_vote_resp(source, resp.clone());
    let post = state_json(eng, false);
    emit(
        "HandleVoteResponse",
        eng.config.id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&resp.vote),
            "last_log": log_json(resp.last_log_id.as_ref(), source),
            "granted": resp.vote_granted,
        }),
    )
}

fn ev_vote_req(eng: &mut Engine<UTConfig>, source: u64, req: VoteRequest<UTConfig>) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    let resp = eng.handle_vote_req(req.clone());
    let post = state_json(eng, false);
    emit(
        "HandleVoteRequest",
        eng.config.id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), source),
            "transfer": req.leadership_transfer,
            "response_vote": vote_json(&resp.vote),
            "response_granted": resp.vote_granted,
        }),
    )
}

fn ev_pre_vote_req(eng: &mut Engine<UTConfig>, source: u64, req: VoteRequest<UTConfig>) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    let resp = eng.handle_pre_vote_req(req.clone());
    let post = state_json(eng, false);
    emit(
        "HandlePreVoteRequest",
        eng.config.id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), source),
            "response_vote": vote_json(&resp.vote),
            "response_last_log": log_json(resp.last_log_id.as_ref(), eng.config.id),
            "response_granted": resp.vote_granted,
        }),
    )
}

/// Delivers a Pre-Vote response that RaftCore's filter would pass:
/// `candidate_vote` is the probe the request carried
/// (core/raft_core.rs:1803-1820,2067-2090).
fn ev_pre_vote_resp(
    eng: &mut Engine<UTConfig>,
    source: u64,
    resp: VoteResponse<UTConfig>,
    candidate_vote: UTVote,
) -> anyhow::Result<()> {
    let pre = state_json(eng, false);
    eng.handle_pre_vote_resp(source, resp.clone());
    let post = state_json(eng, false);
    emit(
        "HandlePreVoteResponse",
        eng.config.id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&resp.vote),
            "last_log": log_json(resp.last_log_id.as_ref(), source),
            "granted": resp.vote_granted,
            "candidate_vote": vote_json(&candidate_vote),
        }),
    )
}

fn ev_heartbeat(eng: &mut Engine<UTConfig>, source: u64, vote: UTVote) -> anyhow::Result<()> {
    let prev = eng.state.last_log_id().cloned();
    let pre = state_json(eng, false);
    let _ = eng.append_entries(&vote, LogSegment::new(prev.clone(), vec![]));
    let post = state_json(eng, false);
    emit(
        "HandleAppendEntries",
        eng.config.id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "vote": vote_json(&vote),
            "prev_log": log_json(prev.as_ref(), source),
        }),
    )
}

fn expired_follower(id: u64, leader: u64, term: u64) -> Engine<UTConfig> {
    let mut eng = base_engine(id, vec![btreeset! {1, 2, 3}], 1);
    // Committed vote of another leader whose lease has expired (duration 0).
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(term, leader));
    eng.output.clear_commands();
    eng
}

// ------------------------------- V0 scenarios -------------------------------

#[test]
fn specula_trace_start_election() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(1, 2));
    ev_elect(&mut eng)
}

#[test]
fn specula_trace_reject_stale_log() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.output.clear_commands();
    ev_vote_req(&mut eng, 2, VoteRequest {
        vote: Vote::new(3, 2),
        last_log_id: Some(log_id(1, 2, 3)),
        leadership_transfer: false,
    })
}

#[test]
fn specula_trace_grant_greater_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.output.clear_commands();
    ev_vote_req(&mut eng, 2, VoteRequest {
        vote: Vote::new(3, 2),
        last_log_id: Some(log_id(2, 1, 3)),
        leadership_transfer: false,
    })
}

#[test]
fn specula_trace_establish_leader() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}], 0);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::from_millis(500), Vote::new(2, 1));
    eng.state.server_state = ServerState::Candidate;
    let candidate = eng.new_candidate(*eng.state.vote_ref());
    candidate.grant_by(&1);
    eng.output.clear_commands();
    ev_vote_resp(&mut eng, 2, VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 0)), true))
}

#[test]
fn specula_trace_append_joint_membership() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}], 1);
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(500),
        Vote::new_committed(2, 1),
    );
    eng.state.server_state = ServerState::Leader;
    eng.testing_new_leader();
    eng.output.clear_commands();
    let target = btreeset! {2, 3};
    let pre = state_json(&eng, false);
    eng.try_leader_handler()?.leader_append_entries([EntryPayload::Membership(membership(vec![
        btreeset! {1, 2},
        target.clone(),
    ]))]);
    let post = state_json(&eng, false);
    emit(
        "AppendJointConfig",
        1,
        pre,
        post,
        json!({"target_config": target.iter().map(u64::to_string).collect::<Vec<_>>() }),
    )
}

#[test]
fn specula_trace_commit_membership() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}], 1);
    let old = stored(1, vec![btreeset! {1, 2}]);
    let joint = stored(2, vec![btreeset! {1, 2}, btreeset! {2, 3}]);
    eng.state.membership_state = MembershipState::new(old, joint);
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, 2)]);
    eng.state.apply_progress_mut().accept(log_id(1, 1, 1));
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(500),
        Vote::new_committed(2, 1),
    );
    eng.state.server_state = ServerState::Leader;
    eng.testing_new_leader();
    eng.output.clear_commands();
    let pre = state_json(&eng, false);
    eng.state.update_local_committed(&Some(log_id(1, 1, 2)));
    let post = state_json(&eng, false);
    emit("CommitMembership", 1, pre, post, json!({}))
}

#[test]
fn specula_trace_restart_follower() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::without_last_update(Vote::new(2, 2));
    eng.state.server_state = ServerState::Learner;
    eng.output.clear_commands();
    let pre = state_json(&eng, true);
    eng.startup();
    let post = state_json(&eng, false);
    emit("Restart", 1, pre, post, json!({}))
}

// ----------------------- Update (Pre-Vote) scenarios ------------------------

/// U1: a follower whose leader lease expired starts a round (external trigger).
#[test]
fn specula_trace_prevote_start() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    ev_pre_elect(&mut eng, "external")
}

/// U1: the election tick's Pre-Vote path, including its seen_greater_log reset.
#[test]
fn specula_trace_prevote_tick_start() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    eng.set_greater_log();
    ev_pre_elect(&mut eng, "tick")
}

/// U5: a single voter's self-grant is already a quorum, so pre_elect elects.
#[test]
fn specula_trace_prevote_single_voter() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    eng.output.clear_commands();
    ev_pre_elect(&mut eng, "external")
}

/// U1: responder grants without any state change (lease expired, log equal).
#[test]
fn specula_trace_prevote_req_grant() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    ev_pre_vote_req(&mut eng, 3, VoteRequest::new(Vote::new(2, 3), Some(log_id(1, 1, 1))))
}

/// U1: responder under a live committed leader lease rejects.
#[test]
fn specula_trace_prevote_req_reject_lease() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(5000),
        Vote::new_committed(1, 2),
    );
    eng.output.clear_commands();
    ev_pre_vote_req(&mut eng, 3, VoteRequest::new(Vote::new(2, 3), Some(log_id(1, 1, 1))))
}

/// U1: responder with a greater last log rejects.
#[test]
fn specula_trace_prevote_req_reject_log() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    ev_pre_vote_req(&mut eng, 3, VoteRequest::new(Vote::new(2, 3), Some(log_id(1, 1, 0))))
}

/// U1: responder whose vote is greater than the probe rejects.
#[test]
fn specula_trace_prevote_req_reject_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 2));
    eng.output.clear_commands();
    ev_pre_vote_req(&mut eng, 3, VoteRequest::new(Vote::new(2, 1), Some(log_id(1, 1, 1))))
}

/// U1/U4: quorum of Pre-Vote grants starts the real election; the runtime's
/// local vote response follows; a late grant for the finished round is ignored.
#[test]
fn specula_trace_prevote_resp_quorum_elect() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    ev_pre_elect(&mut eng, "external")?;
    let probe = Vote::new(2, 1);
    run_commands(&mut eng);
    ev_pre_vote_resp(
        &mut eng,
        2,
        VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 1, 1)), true),
        probe,
    )?;
    let saved = run_commands(&mut eng).expect("candidate vote saved");
    ev_vote_resp(&mut eng, 1, VoteResponse::new(saved, None, true))?;
    run_commands(&mut eng);
    ev_pre_vote_resp(
        &mut eng,
        3,
        VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 1, 1)), true),
        probe,
    )
}

/// U1: a rejection carrying a greater last log marks seen_greater_log.
#[test]
fn specula_trace_prevote_resp_reject_greater_log() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    ev_pre_elect(&mut eng, "external")?;
    run_commands(&mut eng);
    ev_pre_vote_resp(
        &mut eng,
        2,
        VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 2, 2)), false),
        Vote::new(2, 1),
    )
}

/// U1/U3: joint config {1,2},{2,3}: one grant is not a joint quorum, the
/// second completes it and elects.
#[test]
fn specula_trace_prevote_joint_grant_then_elect() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}, btreeset! {2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    eng.output.clear_commands();
    ev_pre_elect(&mut eng, "external")?;
    run_commands(&mut eng);
    let probe = Vote::new(2, 1);
    let grant = VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 1, 1)), true);
    ev_pre_vote_resp(&mut eng, 2, grant.clone(), probe)?;
    ev_pre_vote_resp(&mut eng, 3, grant, probe)
}

/// U4: leader contact (heartbeat with an equal committed vote) cancels the round.
#[test]
fn specula_trace_prevote_cleared_by_heartbeat() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    ev_pre_elect(&mut eng, "external")?;
    run_commands(&mut eng);
    ev_heartbeat(&mut eng, 2, Vote::new_committed(1, 2))
}

/// U4: granting another candidate's real vote cancels the round.
#[test]
fn specula_trace_prevote_cleared_by_vote_grant() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    ev_pre_elect(&mut eng, "external")?;
    run_commands(&mut eng);
    ev_vote_req(&mut eng, 3, VoteRequest {
        vote: Vote::new(2, 3),
        last_log_id: Some(log_id(1, 1, 1)),
        leadership_transfer: false,
    })
}

/// U2: a Candidate whose election timer expires starts a Pre-Vote round (tick
/// path) while its real candidate remains; a late real grant makes it Leader;
/// a Pre-Vote grant for the earlier round then reaches handle_pre_vote_resp.
#[test]
fn specula_trace_stale_prevote_after_win() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    // Real election at term 2.
    ev_elect(&mut eng)?;
    let saved = run_commands(&mut eng).expect("candidate vote saved");
    ev_vote_resp(&mut eng, 1, VoteResponse::new(saved, None, true))?;
    // Election timeout as Candidate: the tick takes the Pre-Vote path.
    ev_pre_elect(&mut eng, "tick")?;
    run_commands(&mut eng);
    // Late real grant from node 2 completes the term-2 quorum.
    ev_vote_resp(&mut eng, 2, VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true))?;
    run_commands(&mut eng);
    // Grant for the Pre-Vote round (probe (3,1)) from node 3.
    ev_pre_vote_resp(
        &mut eng,
        3,
        VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 1)), true),
        Vote::new(3, 1),
    )
}

/// U4: a Candidate holding a Pre-Vote round adopts a higher vote carried by a
/// rejected real vote response; become_following drops both trackers.
#[test]
fn specula_trace_prevote_cleared_by_higher_vote_resp() -> anyhow::Result<()> {
    let mut eng = expired_follower(1, 2, 1);
    ev_elect(&mut eng)?;
    let saved = run_commands(&mut eng).expect("candidate vote saved");
    ev_vote_resp(&mut eng, 1, VoteResponse::new(saved, None, true))?;
    ev_pre_elect(&mut eng, "tick")?;
    run_commands(&mut eng);
    ev_vote_resp(&mut eng, 2, VoteResponse::new(Vote::new(2, 2), Some(log_id(1, 1, 1)), false))
}

fn empty_log_follower(id: u64) -> Engine<UTConfig> {
    let mut eng = base_engine(id, vec![btreeset! {1, 2, 3}], 1);
    eng.state.log_ids = LogIdList::new(None, Vec::new());
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(0, 2));
    eng.output.clear_commands();
    eng
}

/// Repair check: requester and responder both have no log (None == None).
#[test]
fn specula_trace_prevote_req_grant_empty_logs() -> anyhow::Result<()> {
    let mut eng = empty_log_follower(1);
    ev_pre_vote_req(&mut eng, 3, VoteRequest::new(Vote::new(1, 3), None))
}

/// Repair check on the V0 path: a real vote request with no logs on either side.
#[test]
fn specula_trace_grant_vote_empty_logs() -> anyhow::Result<()> {
    let mut eng = empty_log_follower(1);
    ev_vote_req(&mut eng, 3, VoteRequest {
        vote: Vote::new(1, 3),
        last_log_id: None,
        leadership_transfer: false,
    })
}
