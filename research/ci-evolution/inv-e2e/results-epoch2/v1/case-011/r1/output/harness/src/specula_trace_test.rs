//! Specula trace harness (V0 rebased onto the Pre-Vote revision).
//!
//! This module is test-only instrumentation. It invokes the real Engine
//! transitions directly and records only source-observable abstract state.
//!
//! Rebase notes (incremental run):
//! - V0 single-transition scenarios are kept with identical setups.
//! - State capture adds the Pre-Vote candidate (`Engine::pre_candidate`), the
//!   real frozen quorum of the candidate and pre-candidate
//!   (`Candidate::progress().quorum_set()`), and whether a queued log append
//!   sits behind a queued SaveVote (`append_behind_vote`).
//! - Update scenarios are multi-event. Between events the harness drains the
//!   engine output exactly as `RaftCore::run_engine_commands` would execute
//!   it (SaveVote durable, SendVote/SendPreVote dispatched, AppendEntries
//!   flushed); `Trace.tla` reaches the next pre-state with constrained silent
//!   PersistVote / SendVoteRequest / FinishVoteBroadcast / FlushLog steps.

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
use crate::testing::blank_ent;
use crate::type_config::TypeConfigExt;
use crate::type_config::alias::StoredMembershipOf;
use crate::utime::Leased;

type V = Vote<crate::engine::testing::UTLeaderId>;

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

fn vote_json(v: &V) -> Value {
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
    let parts = parts.iter().map(|part| part.iter().map(u64::to_string).collect::<Vec<_>>()).collect::<Vec<_>>();
    json!(parts)
}

fn config_json(m: &StoredMembershipOf<UTConfig>) -> Value {
    parts_json(m.get_joint_config())
}

fn state_json(eng: &Engine<UTConfig>, crashed: bool) -> Value {
    let effective = eng.state.membership_state.effective();
    let committed = eng.state.membership_state.committed();

    let candidate = eng.candidate_ref();
    let candidate_vote = candidate.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let grants = candidate.map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>()).unwrap_or_default();
    // Real frozen quorum of the candidate (proposer/candidate.rs:66-80).
    let candidate_config = candidate
        .map(|x| parts_json(x.progress().quorum_set().get_joint_config()))
        .unwrap_or_else(|| config_json(effective));

    // Pre-Vote candidate (engine_impl.rs:95-101,148-165).
    let pre = eng.pre_candidate_ref();
    let pre_vote = pre.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let pre_grants = pre.map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>()).unwrap_or_default();
    let pre_config = pre
        .map(|x| parts_json(x.progress().quorum_set().get_joint_config()))
        .unwrap_or_else(|| config_json(effective));

    let has_command = |name| eng.output.iter_commands().any(|cmd| cmd.name() == name);
    // FIFO command order (engine_output.rs): an AppendEntries queued after a
    // SaveVote cannot be submitted before the vote is durable.
    let mut seen_save = false;
    let mut append_behind_vote = false;
    for cmd in eng.output.iter_commands() {
        match cmd.name() {
            CommandName::SaveVote => seen_save = true,
            CommandName::AppendEntries if seen_save => append_behind_vote = true,
            _ => {}
        }
    }

    let (last_update, lease, enabled) = eng.state.vote.lease_info();
    let lease_valid = enabled
        && last_update.is_some()
        && !eng.state.vote.is_expired(UTConfig::<()>::now(), Duration::default())
        && !lease.is_zero();

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
        "pre_candidate_active": pre.is_some(),
        "pre_candidate_vote": vote_json(pre_vote),
        "pre_grants": pre_grants,
        "pre_candidate_config": pre_config,
        "save_vote_pending": has_command(CommandName::SaveVote),
        "send_vote_pending": has_command(CommandName::SendVote),
        "send_pre_vote_pending": has_command(CommandName::SendPreVote),
        "append_pending": has_command(CommandName::AppendEntries),
        "append_behind_vote": append_behind_vote,
        "seen_greater_log": eng.is_there_greater_log(),
        "crashed": crashed,
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

/// Capture one engine transition, then let the "runtime" execute every queued
/// command (raft_core.rs run_engine_commands: SaveVote awaited, SendVote /
/// SendPreVote dispatched, AppendEntries submitted and flushed).
fn step<F>(eng: &mut Engine<UTConfig>, name: &str, f: F) -> anyhow::Result<()>
where F: FnOnce(&mut Engine<UTConfig>) -> Value {
    let nid = eng.config.id;
    let pre = state_json(eng, false);
    let mut args = f(eng);
    let post = state_json(eng, false);
    // Record the dispatched Pre-Vote / Vote requests of this transition.
    let mut pre_vote_req = json!({"present": false});
    let mut vote_req = json!({"present": false});
    for cmd in eng.output.iter_commands() {
        match cmd {
            Command::SendPreVote { vote_req: r } => {
                pre_vote_req = json!({"present": true, "vote": vote_json(&r.vote), "last_log": log_json(r.last_log_id.as_ref(), nid)})
            }
            Command::SendVote { vote_req: r } => {
                vote_req = json!({"present": true, "vote": vote_json(&r.vote), "last_log": log_json(r.last_log_id.as_ref(), nid)})
            }
            _ => {}
        }
    }
    if let Value::Object(map) = &mut args {
        map.insert("send_pre_vote".to_string(), pre_vote_req);
        map.insert("send_vote".to_string(), vote_req);
    }
    emit(name, nid, pre, post, args)?;
    eng.output.take_commands();
    Ok(())
}

fn pre_vote_req_args(source: u64, req: &VoteRequest<UTConfig>, resp: &VoteResponse<UTConfig>, responder: u64) -> Value {
    json!({
        "source": source.to_string(),
        "vote": vote_json(&req.vote),
        "last_log": log_json(req.last_log_id.as_ref(), source),
        "transfer": req.leadership_transfer,
        "response_vote": vote_json(&resp.vote),
        "response_granted": resp.vote_granted,
        "response_last_log": log_json(resp.last_log_id.as_ref(), responder),
    })
}

fn pre_vote_resp_args(source: u64, resp: &VoteResponse<UTConfig>, round: &V) -> Value {
    json!({
        "source": source.to_string(),
        "vote": vote_json(&resp.vote),
        "last_log": log_json(resp.last_log_id.as_ref(), source),
        "granted": resp.vote_granted,
        "round": vote_json(round),
    })
}

fn vote_resp_args(source: u64, resp: &VoteResponse<UTConfig>) -> Value {
    json!({
        "source": source.to_string(),
        "vote": vote_json(&resp.vote),
        "last_log": log_json(resp.last_log_id.as_ref(), source),
        "granted": resp.vote_granted,
    })
}

// ---------------------------------------------------------------------------
// V0 regression scenarios (setups unchanged)
// ---------------------------------------------------------------------------

#[test]
fn specula_trace_start_election() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(1, 2));
    let pre = state_json(&eng, false);
    eng.elect();
    let post = state_json(&eng, false);
    emit("StartElection", 1, pre, post, json!({"transfer": false}))
}

#[test]
fn specula_trace_reject_stale_log() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.output.clear_commands();
    let req = VoteRequest {
        vote: Vote::new(3, 2),
        last_log_id: Some(log_id(1, 2, 3)),
        leadership_transfer: false,
    };
    let pre = state_json(&eng, false);
    let resp = eng.handle_vote_req(req.clone());
    let post = state_json(&eng, false);
    emit(
        "HandleVoteRequest",
        1,
        pre,
        post,
        json!({
            "source": "2",
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), 2),
            "transfer": req.leadership_transfer,
            "response_vote": vote_json(&resp.vote),
            "response_granted": resp.vote_granted,
        }),
    )
}

#[test]
fn specula_trace_grant_greater_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(2, 1, 3)]);
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.output.clear_commands();
    let req = VoteRequest {
        vote: Vote::new(3, 2),
        last_log_id: Some(log_id(2, 1, 3)),
        leadership_transfer: false,
    };
    let pre = state_json(&eng, false);
    let resp = eng.handle_vote_req(req.clone());
    let post = state_json(&eng, false);
    emit(
        "HandleVoteRequest",
        1,
        pre,
        post,
        json!({
            "source": "2",
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), 2),
            "transfer": req.leadership_transfer,
            "response_vote": vote_json(&resp.vote),
            "response_granted": resp.vote_granted,
        }),
    )
}

#[test]
fn specula_trace_establish_leader() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}], 0);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::from_millis(500), Vote::new(2, 1));
    eng.state.server_state = ServerState::Candidate;
    let candidate = eng.new_candidate(*eng.state.vote_ref());
    candidate.grant_by(&1);
    eng.output.clear_commands();
    let response = VoteResponse::new(Vote::new(2, 1), Some(log_id(1, 1, 0)), true);
    let pre = state_json(&eng, false);
    eng.handle_vote_resp(2, response.clone());
    let post = state_json(&eng, false);
    emit(
        "HandleVoteResponse",
        1,
        pre,
        post,
        json!({
            "source": "2",
            "vote": vote_json(&response.vote),
            "last_log": log_json(response.last_log_id.as_ref(), 2),
            "granted": response.vote_granted,
        }),
    )
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

// ---------------------------------------------------------------------------
// Update-focused scenarios (Pre-Vote revision). Each names the model Actions
// it exercises; see instrumentation-spec.md section 4.
// ---------------------------------------------------------------------------

/// U-T1: PreElect -> granted PreVoteResp reaches quorum -> real election.
/// Actions: PreElect, HandlePreVoteResponse(wins) -> DoElect.
#[test]
fn specula_trace_prevote_quorum_elect() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    // Committed vote of leader 2 whose lease has expired.
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    step(&mut eng, "PreElect", |e| {
        e.pre_elect();
        json!({})
    })?;
    let round = *eng.pre_candidate_ref().unwrap().vote_ref();
    let resp = VoteResponse::new(Vote::new_committed(1, 2), Some(log_id(1, 1, 1)), true);
    step(&mut eng, "HandlePreVoteResponse", |e| {
        e.handle_pre_vote_resp(2, resp.clone());
        pre_vote_resp_args(2, &resp, &round)
    })
}

/// U-T2: a rejected Pre-Vote whose responder holds a higher vote leaves the
/// requester's vote unchanged, and the next round probes the same term.
/// Actions: PreElect, HandlePreVoteResponse(rejected), PreElect.
#[test]
fn specula_trace_prevote_reject_higher_vote() -> anyhow::Result<()> {
    let mut eng = base_engine(2, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 1));
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, 2)]);
    step(&mut eng, "PreElect", |e| {
        e.pre_elect();
        json!({})
    })?;
    let round = *eng.pre_candidate_ref().unwrap().vote_ref();
    // Responder 3 already voted (2,3) and has a shorter log.
    let resp = VoteResponse::new(Vote::new(2, 3), Some(log_id(1, 1, 1)), false);
    step(&mut eng, "HandlePreVoteResponse", |e| {
        e.handle_pre_vote_resp(3, resp.clone());
        pre_vote_resp_args(3, &resp, &round)
    })?;
    step(&mut eng, "PreElect", |e| {
        e.pre_elect();
        json!({})
    })
}

/// U-T3: responder side of a Pre-Vote: rejected by a higher local vote, by a
/// longer local log, and by the leader lease; granted otherwise. No state
/// changes in any case. Actions: HandlePreVoteRequest (4 branches).
#[test]
fn specula_trace_prevote_request_branches() -> anyhow::Result<()> {
    let mut eng = base_engine(3, vec![btreeset! {1, 2, 3}], 1);
    // Node 3 is a candidate at (2,3) with a short log.
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 3));
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, 1)]);
    eng.state.server_state = ServerState::Candidate;
    eng.new_candidate(*eng.state.vote_ref());
    eng.output.clear_commands();

    // (a) lower pre-vote (2,2) from a longer log: rejected by vote order.
    let req = VoteRequest::new(Vote::new(2, 2), Some(log_id(1, 1, 2)));
    step(&mut eng, "HandlePreVoteRequest", |e| {
        let resp = e.handle_pre_vote_req(req.clone());
        pre_vote_req_args(2, &req, &resp, 3)
    })?;
    // (b) higher pre-vote (3,1) from a shorter log: rejected by last log id.
    let req = VoteRequest::new(Vote::new(3, 1), None);
    step(&mut eng, "HandlePreVoteRequest", |e| {
        let resp = e.handle_pre_vote_req(req.clone());
        pre_vote_req_args(1, &req, &resp, 3)
    })?;
    // (c) higher pre-vote from an equal log: granted, nothing changes.
    let req = VoteRequest::new(Vote::new(3, 2), Some(log_id(1, 1, 1)));
    step(&mut eng, "HandlePreVoteRequest", |e| {
        let resp = e.handle_pre_vote_req(req.clone());
        pre_vote_req_args(2, &req, &resp, 3)
    })?;

    Ok(())
}

/// U-T3d: a follower holding a live leader lease rejects a Pre-Vote even from
/// an up-to-date candidate (Pre-Vote is never a leadership transfer).
/// Actions: HandlePreVoteRequest (lease branch).
#[test]
fn specula_trace_prevote_request_lease() -> anyhow::Result<()> {
    let mut eng = base_engine(3, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(5000),
        Vote::new_committed(1, 1),
    );
    let req = VoteRequest::new(Vote::new(2, 2), Some(log_id(1, 1, 1)));
    step(&mut eng, "HandlePreVoteRequest", |e| {
        let resp = e.handle_pre_vote_req(req.clone());
        pre_vote_req_args(2, &req, &resp, 3)
    })
}

/// U-T4: a candidate re-runs Pre-Vote on a later tick, then wins its ongoing
/// real election; the surviving pre-candidate's quorum then starts a new
/// election on the established leader.
/// Actions: StartElection, (silent PersistVote, SendVoteRequest,
/// FinishVoteBroadcast), HandleVoteResponse(self), PreElect,
/// HandleVoteResponse(wins), (silent PersistVote, FlushLog),
/// HandlePreVoteResponse(wins) -> DoElect.
#[test]
fn specula_trace_candidate_prevote_then_establish() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(0, 2));
    step(&mut eng, "StartElection", |e| {
        e.elect();
        json!({"transfer": false})
    })?;
    let cand_vote = *eng.state.vote_ref();
    // raft_core.rs:2292-2300: after SaveVote, the runtime feeds the local grant.
    let self_resp = VoteResponse::new(cand_vote, None, true);
    step(&mut eng, "HandleVoteResponse", |e| {
        e.handle_vote_resp(1, self_resp.clone());
        vote_resp_args(1, &self_resp)
    })?;
    // A later election tick (multi-voter, pre-vote enabled) runs pre_elect.
    step(&mut eng, "PreElect", |e| {
        e.pre_elect();
        json!({})
    })?;
    let round = *eng.pre_candidate_ref().unwrap().vote_ref();
    // Node 2's real vote grant arrives: quorum, leader established.
    let resp2 = VoteResponse::new(cand_vote, Some(log_id(1, 1, 1)), true);
    step(&mut eng, "HandleVoteResponse", |e| {
        e.handle_vote_resp(2, resp2.clone());
        vote_resp_args(2, &resp2)
    })?;
    // Node 3 granted the pre-vote (its vote (1,1) <= (2,1), no lease).
    let pre_resp = VoteResponse::new(cand_vote, Some(log_id(1, 1, 1)), true);
    step(&mut eng, "HandlePreVoteResponse", |e| {
        e.handle_pre_vote_resp(3, pre_resp.clone());
        pre_vote_resp_args(3, &pre_resp, &round)
    })
}

/// U-T5: an AppendEntries from the current leader clears an in-flight
/// pre-candidate (become_following) and extends the follower log.
/// Actions: PreElect, HandleAppendEntries.
#[test]
fn specula_trace_prevote_cleared_by_append() -> anyhow::Result<()> {
    let mut eng = base_engine(2, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 1));
    step(&mut eng, "PreElect", |e| {
        e.pre_elect();
        json!({})
    })?;
    let leader_vote = Vote::new_committed(1, 1);
    step(&mut eng, "HandleAppendEntries", |e| {
        let seg = LogSegment::new(Some(log_id(1, 1, 1)), vec![blank_ent::<UTConfig>(1, 1, 2)]);
        let res = e.append_entries(&leader_vote, seg);
        json!({
            "source": "1",
            "vote": vote_json(&leader_vote),
            "last_log": log_json(Some(&log_id(1, 1, 2)), 1),
            "ok": res.is_ok(),
        })
    })
}

/// U-T6: granting a real vote request clears an in-flight pre-candidate.
/// Actions: PreElect, HandleVoteRequest(strict grant).
#[test]
fn specula_trace_prevote_cleared_by_vote_grant() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    step(&mut eng, "PreElect", |e| {
        e.pre_elect();
        json!({})
    })?;
    let req = VoteRequest {
        vote: Vote::new(2, 3),
        last_log_id: Some(log_id(1, 1, 1)),
        leadership_transfer: false,
    };
    step(&mut eng, "HandleVoteRequest", |e| {
        let resp = e.handle_vote_req(req.clone());
        json!({
            "source": "3",
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), 3),
            "transfer": req.leadership_transfer,
            "response_vote": vote_json(&resp.vote),
            "response_granted": resp.vote_granted,
        })
    })
}

/// U-T7: a single voter wins its own pre-vote and elects directly.
/// Actions: PreElect (self-quorum branch -> DoElect).
#[test]
fn specula_trace_prevote_single_voter() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new_committed(1, 2));
    eng.state.server_state = ServerState::Follower;
    step(&mut eng, "PreElect", |e| {
        e.pre_elect();
        json!({})
    })
}

/// U-T8 (repair R-5 evidence): two nodes without any log. `None >= None`, so
/// both a Pre-Vote and a real vote from an empty-log requester are granted.
/// Actions: HandlePreVoteRequest(grant), HandleVoteRequest(strict grant).
#[test]
fn specula_trace_grant_empty_logs() -> anyhow::Result<()> {
    let mut eng = base_engine(2, vec![btreeset! {1, 2, 3}], 1);
    eng.state.log_ids = LogIdList::new(None, Vec::<crate::type_config::alias::LogIdOf<UTConfig>>::new());
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(0, 2));
    let req = VoteRequest::new(Vote::new(1, 1), None);
    step(&mut eng, "HandlePreVoteRequest", |e| {
        let resp = e.handle_pre_vote_req(req.clone());
        pre_vote_req_args(1, &req, &resp, 2)
    })?;
    step(&mut eng, "HandleVoteRequest", |e| {
        let resp = e.handle_vote_req(req.clone());
        json!({
            "source": "1",
            "vote": vote_json(&req.vote),
            "last_log": log_json(req.last_log_id.as_ref(), 1),
            "transfer": req.leadership_transfer,
            "response_vote": vote_json(&resp.vote),
            "response_granted": resp.vote_granted,
        })
    })
}
