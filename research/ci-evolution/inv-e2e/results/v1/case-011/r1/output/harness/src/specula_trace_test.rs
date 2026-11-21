//! Specula trace harness (V0 rebased onto the Pre-Vote update, V1).
//!
//! This module is test-only instrumentation. It invokes real Engine
//! transitions directly and records only source-observable abstract state.
//! The V0 single-transition scenarios are kept unchanged except that every
//! record now also carries the pre-candidate fields introduced by the update
//! and the real `seen_greater_log` value (V0 hard-coded `false`).
//!
//! Update scenarios (U-S*) drive several engine events on one node. Between
//! two events the harness drains the command queue the way RaftCore does after
//! every event; the Trace spec replays the corresponding runtime completions
//! (PersistVote, FlushLog, vote/pre-vote dispatch) as guarded silent steps.
//! Only notifications that RaftCore would forward are fed to the engine
//! (raft_core.rs: does_candidate_vote_match / does_pre_candidate_vote_match).

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
use crate::engine::CommandName;
use crate::engine::Engine;
use crate::engine::LogIdList;
use crate::engine::testing::UTConfig;
use crate::engine::testing::log_id;
use crate::entry::payload::EntryPayload;
use crate::raft::LogSegment;
use crate::raft::VoteRequest;
use crate::raft::VoteResponse;
use crate::raft_state::LogStateReader;
use crate::type_config::TypeConfigExt;
use crate::type_config::alias::StoredMembershipOf;
use crate::utime::Leased;

type UTVote = Vote<crate::engine::testing::UTLeaderId>;
type UTLogId = crate::type_config::alias::LogIdOf<UTConfig>;

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

fn log_json(log: Option<&UTLogId>, node: u64) -> Value {
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

fn config_json(m: &StoredMembershipOf<UTConfig>) -> Value {
    let parts = m
        .get_joint_config()
        .iter()
        .map(|part| part.iter().map(u64::to_string).collect::<Vec<_>>())
        .collect::<Vec<_>>();
    json!(parts)
}

fn state_json(eng: &Engine<UTConfig>, crashed: bool) -> Value {
    let candidate = eng.candidate_ref();
    let candidate_vote = candidate.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let grants = candidate
        .map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>())
        .unwrap_or_default();
    // UPDATE: Engine.pre_candidate (engine_impl.rs:95-101)
    let pre = eng.pre_candidate_ref();
    let pre_vote = pre.map(|x| x.vote_ref()).unwrap_or_else(|| eng.state.vote_ref());
    let pre_last_log = pre.and_then(|x| x.last_log_id());
    let pre_grants = pre
        .map(|x| x.granters().map(|id| id.to_string()).collect::<Vec<_>>())
        .unwrap_or_default();
    let has_command = |name| eng.output.iter_commands().any(|cmd| cmd.name() == name);
    let (last_update, lease, enabled) = eng.state.vote.lease_info();
    let lease_valid = enabled
        && last_update.is_some()
        && !eng.state.vote.is_expired(UTConfig::<()>::now(), Duration::default())
        && !lease.is_zero();
    let committed = eng.state.membership_state.committed();
    let effective = eng.state.membership_state.effective();

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
        // Candidate keeps an internal frozen quorum. In these scenarios it is
        // equal to the observable effective membership at election creation.
        "candidate_config": config_json(effective),
        "grants": grants,
        "leader_active": eng.leader_ref().is_some(),
        "save_vote_pending": has_command(CommandName::SaveVote),
        "send_vote_pending": has_command(CommandName::SendVote),
        "append_pending": has_command(CommandName::AppendEntries),
        // V1: the real engine flag (V0 serialized a constant false).
        "seen_greater_log": eng.seen_greater_log,
        "crashed": crashed,
        // UPDATE fields
        "pre_candidate_active": pre.is_some(),
        "pre_candidate_vote": vote_json(pre_vote),
        "pre_candidate_last_log": log_json(pre_last_log, eng.config.id),
        // Same frozen-quorum observation rule as candidate_config: no membership
        // change happens while a pre-candidate exists in these scenarios.
        "pre_candidate_config": config_json(effective),
        "pre_grants": pre_grants,
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

/// Record an observation that is not a model transition (e.g. a debug
/// assertion outcome) next to the trace file.
fn observe(name: &str, value: Value) -> anyhow::Result<()> {
    let path = std::env::var("SPECULA_TRACE_PATH")? + ".observation.json";
    let mut out = OpenOptions::new().create(true).append(true).open(path)?;
    serde_json::to_writer(&mut out, &json!({"observation": name, "value": value}))?;
    writeln!(&mut out)?;
    Ok(())
}

// ----------------------------------------------------------------------------
// Event drivers shared by the update scenarios. Each drains the command queue
// first (RaftCore runs all commands of the previous event before the next one).
// ----------------------------------------------------------------------------

fn ev_elect(eng: &mut Engine<UTConfig>) -> anyhow::Result<()> {
    eng.output.clear_commands();
    let pre = state_json(eng, false);
    eng.elect();
    let post = state_json(eng, false);
    emit("StartElection", eng.config.id, pre, post, json!({"transfer": false}))
}

fn ev_pre_elect(eng: &mut Engine<UTConfig>) -> anyhow::Result<()> {
    eng.output.clear_commands();
    let pre = state_json(eng, false);
    eng.pre_elect();
    let post = state_json(eng, false);
    emit("PreElect", eng.config.id, pre, post, json!({}))
}

fn ev_vote_resp(eng: &mut Engine<UTConfig>, source: u64, resp: VoteResponse<UTConfig>) -> anyhow::Result<()> {
    eng.output.clear_commands();
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
    eng.output.clear_commands();
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
    eng.output.clear_commands();
    let pre = state_json(eng, false);
    let resp = eng.handle_pre_vote_req(req.clone());
    let commands_after = eng.output.iter_commands().count();
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
            "commands_emitted": commands_after,
        }),
    )
}

/// `candidate_vote` is the pre-vote request vote that the RaftCore
/// notification carries (raft_core.rs:1440-1458); RaftCore forwards the
/// response only if it matches the current pre-candidate (raft_core.rs:1815).
fn ev_pre_vote_resp(
    eng: &mut Engine<UTConfig>,
    source: u64,
    candidate_vote: UTVote,
    resp: VoteResponse<UTConfig>,
) -> anyhow::Result<()> {
    eng.output.clear_commands();
    let pre = state_json(eng, false);
    let forwarded = eng
        .pre_candidate_ref()
        .map(|pc| pc.vote_ref().leader_id() == candidate_vote.leader_id())
        .unwrap_or(false);
    if forwarded {
        eng.handle_pre_vote_resp(source, resp.clone());
    }
    let post = state_json(eng, false);
    emit(
        "HandlePreVoteResponse",
        eng.config.id,
        pre,
        post,
        json!({
            "source": source.to_string(),
            "candidate_vote": vote_json(&candidate_vote),
            "vote": vote_json(&resp.vote),
            "last_log": log_json(resp.last_log_id.as_ref(), source),
            "granted": resp.vote_granted,
            "forwarded_by_runtime": forwarded,
        }),
    )
}

fn ev_append(eng: &mut Engine<UTConfig>, source: u64, vote: UTVote, prev: Option<UTLogId>) -> anyhow::Result<()> {
    eng.output.clear_commands();
    let pre = state_json(eng, false);
    let res = eng.append_entries(&vote, LogSegment::new(prev.clone(), vec![]));
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
            "accepted": res.is_ok(),
        }),
    )
}

// ----------------------------------------------------------------------------
// V0 regression scenarios (unchanged drivers).
// ----------------------------------------------------------------------------

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
    ev_vote_req(&mut eng, 2, req)
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
    ev_vote_req(&mut eng, 2, req)
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
    ev_vote_resp(&mut eng, 2, response)
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

// ----------------------------------------------------------------------------
// Update scenarios derived from the visible diff.
// ----------------------------------------------------------------------------

/// Follower of an uncommitted vote with no lease: the common tick pre-state.
fn follower_engine() -> Engine<UTConfig> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(1, 2));
    eng
}

/// U-S1a: Pre-Vote request granted without mutation (engine_impl.rs:414-447).
#[test]
fn specula_trace_pre_vote_req_grant() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    ev_pre_vote_req(&mut eng, 2, VoteRequest::new(Vote::new(2, 2), Some(log_id(1, 1, 1))))
}

/// U-S1b: an unexpired committed lease rejects; no transfer bypass exists.
#[test]
fn specula_trace_pre_vote_req_reject_lease() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    eng.state.vote = Leased::new(
        UTConfig::<()>::now(),
        Duration::from_millis(5_000),
        Vote::new_committed(1, 3),
    );
    ev_pre_vote_req(&mut eng, 2, VoteRequest::new(Vote::new(2, 2), Some(log_id(1, 1, 1))))
}

/// U-S1c: a candidate with a smaller last log is rejected.
#[test]
fn specula_trace_pre_vote_req_reject_log() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    eng.state.log_ids = LogIdList::new(None, [log_id(1, 1, 3)]);
    ev_pre_vote_req(&mut eng, 2, VoteRequest::new(Vote::new(2, 2), Some(log_id(1, 1, 2))))
}

/// U-S1d: a smaller vote (same term, lower node) is rejected by the order check.
#[test]
fn specula_trace_pre_vote_req_reject_vote() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(2, 3));
    ev_pre_vote_req(&mut eng, 2, VoteRequest::new(Vote::new(2, 2), Some(log_id(1, 1, 1))))
}

/// U-S2a: multi-voter pre_elect leaves vote/role untouched and queues SendPreVote.
#[test]
fn specula_trace_pre_elect_multi() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    ev_pre_elect(&mut eng)
}

/// U-S2b: single-voter pre_elect self-quorum elects at once.
#[test]
fn specula_trace_pre_elect_single() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(1, 1));
    ev_pre_elect(&mut eng)
}

/// U-S2c: pre-vote quorum -> real election (old producer -> affected -> old consumer).
#[test]
fn specula_trace_pre_vote_resp_quorum() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    ev_pre_elect(&mut eng)?;
    let pv = *eng.pre_candidate_ref().unwrap().vote_ref();
    ev_pre_vote_resp(&mut eng, 2, pv, VoteResponse::new(Vote::new(1, 2), Some(log_id(1, 1, 1)), true))?;
    // The real election that follows: the self vote is granted once SaveVote
    // completes (raft_core.rs:2290-2301).
    let v = *eng.state.vote_ref();
    ev_vote_resp(&mut eng, 1, VoteResponse::new(v, None, true))
}

/// U-S2d: a rejection with a greater log only records seen_greater_log.
#[test]
fn specula_trace_pre_vote_resp_reject_greater_log() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    ev_pre_elect(&mut eng)?;
    let pv = *eng.pre_candidate_ref().unwrap().vote_ref();
    ev_pre_vote_resp(&mut eng, 3, pv, VoteResponse::new(Vote::new(1, 2), Some(log_id(1, 2, 2)), false))
}

/// U-S3a: a granted real vote request clears the pre-candidate
/// (become_following, vote_handler/mod.rs:244); a delayed grant is then ignored.
#[test]
fn specula_trace_pre_vote_superseded_by_vote_req() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    ev_pre_elect(&mut eng)?;
    let pv = *eng.pre_candidate_ref().unwrap().vote_ref();
    ev_vote_req(&mut eng, 3, VoteRequest::new(Vote::new(2, 3), Some(log_id(1, 1, 1))))?;
    ev_pre_vote_resp(&mut eng, 2, pv, VoteResponse::new(Vote::new(1, 2), Some(log_id(1, 1, 1)), true))
}

/// U-S3b: AppendEntries from a leader clears the pre-candidate.
#[test]
fn specula_trace_pre_vote_superseded_by_append() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    ev_pre_elect(&mut eng)?;
    ev_append(&mut eng, 2, Vote::new_committed(1, 2), Some(log_id(1, 1, 1)))
}

/// U-S3c: a direct election supersedes the in-flight pre-vote round
/// (do_elect, engine_impl.rs:263-264).
#[test]
fn specula_trace_pre_vote_superseded_by_elect() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    ev_pre_elect(&mut eng)?;
    ev_elect(&mut eng)
}

/// U-S4: a Candidate whose election timer fires runs a Pre-Vote round while
/// its real candidacy is still live (tick: raft_core.rs:1966-2031 skips only
/// Leaders). A delayed real grant establishes it as Leader; establish_leader
/// does not clear the pre-candidate (engine_impl.rs:855-881). The stale
/// pre-vote quorum then calls elect() on the established Leader.
#[test]
fn specula_trace_candidate_pre_vote_then_leader() -> anyhow::Result<()> {
    let mut eng = follower_engine();
    // Real election at term 2 (tick with pre-vote disabled, or a quorum of an
    // earlier pre-vote round; both reach Engine::elect()).
    ev_elect(&mut eng)?;
    let cv = *eng.state.vote_ref();
    // SaveVote completes; RaftCore feeds the local granted response.
    ev_vote_resp(&mut eng, 1, VoteResponse::new(cv, None, true))?;
    // Election timer fires while still Candidate: pre-vote round at term 3.
    ev_pre_elect(&mut eng)?;
    let pv = *eng.pre_candidate_ref().unwrap().vote_ref();
    // Delayed real grant from node 2 for term 2 (candidate vote still matches).
    ev_vote_resp(&mut eng, 2, VoteResponse::new(cv, Some(log_id(1, 1, 1)), true))?;
    observe(
        "leader_established_with_pre_candidate",
        json!({
            "server_state_leader": eng.state.server_state == ServerState::Leader,
            "pre_candidate_active": eng.pre_candidate_ref().is_some(),
        }),
    )?;
    // Node 2, which granted the real term-2 vote and holds no lease, grants the
    // term-3 pre-vote (handle_pre_vote_req); the response arrives now.
    ev_pre_vote_resp(&mut eng, 2, pv, VoteResponse::new(cv, Some(log_id(1, 1, 1)), true))?;

    // Observation (not a model transition): the next heartbeat/client-write
    // path calls try_leader_handler(), whose debug assertion requires
    // leader.committed_vote >= state.vote (engine_impl.rs:977-982).
    let leader_vote = eng.leader_ref().map(|l| l.committed_vote_ref().clone().into_vote());
    let local_vote = *eng.state.vote_ref();
    let res = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let _ = eng.try_leader_handler().is_ok();
    }));
    observe(
        "try_leader_handler_after_pre_vote_elect",
        json!({
            "leader_object_present": leader_vote.is_some(),
            "leader_committed_vote": leader_vote.as_ref().map(vote_json),
            "local_vote": vote_json(&local_vote),
            "debug_assertions": cfg!(debug_assertions),
            "panicked": res.is_err(),
        }),
    )
}

/// U-S2e: joint configuration; a remote grant is accumulated without a quorum
/// (grant_by returns false) and a later grant completes the joint quorum.
#[test]
fn specula_trace_pre_vote_resp_joint_accumulate() -> anyhow::Result<()> {
    let mut eng = base_engine(1, vec![btreeset! {1, 2}, btreeset! {2, 3}], 1);
    eng.state.vote = Leased::new(UTConfig::<()>::now(), Duration::ZERO, Vote::new(1, 2));
    ev_pre_elect(&mut eng)?;
    let pv = *eng.pre_candidate_ref().unwrap().vote_ref();
    ev_pre_vote_resp(&mut eng, 3, pv, VoteResponse::new(Vote::new(1, 2), Some(log_id(1, 1, 1)), true))?;
    ev_pre_vote_resp(&mut eng, 2, pv, VoteResponse::new(Vote::new(1, 2), Some(log_id(1, 1, 1)), true))
}
